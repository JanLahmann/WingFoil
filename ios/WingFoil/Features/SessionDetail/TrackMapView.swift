import CoreLocation
import MapKit
import SwiftUI
import WingFoilKit

/// Track drawn as segmented polylines coloured by phase (flying vs everything else), with
/// the maneuver/flight-end outcomes marked and one GP3S effort highlighted. The inline map
/// is non-interactive so the detail page scrolls; the full-screen version is interactive.
///
/// The map is the second handle on the replay playhead: tapping near the track moves it,
/// and the dot it draws is the same instant the chart and the readout show.
struct TrackMapView: View {
    let detail: SessionDetail
    /// The GP3S effort whose window is glowing on the track, if any.
    let effort: SessionDetail.RecordEffort?
    @Binding var playhead: Double?
    /// Which categories the legend chips are currently showing. Passed in rather than read
    /// here so the drawing stays a pure function of it.
    let visibility: MapLayerVisibility
    /// The flight the chart is framing, when a flying segment has been tapped. Owned by the
    /// page so the map and the chart are the same tap (docs/presentation.md, "Pairing").
    @Binding var flightFocus: SessionDetail.FlightFocus?

    /// Tap-only: nothing about the pairing renders until something is tapped.
    @State private var callout: SessionDetail.Callout?
    /// Bumped on every flight tap; see `SessionDetail.FlightFocus`.
    @State private var focusTick = 0

    /// Direction chevrons for the camera as it stands. State rather than a computed value:
    /// the spacing is measured in screen points, so it is a function of the camera and has
    /// to be rebuilt when the camera moves (see `DirectionField`).
    @State private var direction = DirectionField()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MapReader { proxy in
                Map(initialPosition: .region(detail.initialRegion), interactionModes: []) {
                    TrackContent(detail: detail, effort: effort,
                                 visibility: visibility,
                                 playhead: playhead.flatMap(detail.moment),
                                 direction: direction)
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 260)
                .clipShape(.rect(cornerRadius: 14))
                .onMapCameraChange(frequency: .onEnd) { context in
                    direction.camera(moved: context, detail: detail)
                }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    direction.resized(to: size, detail: detail)
                }
                // Interaction is off so the page scrolls, which leaves the tap free to
                // mean exactly one thing: "show me this point".
                .onTapGesture { location in
                    guard let coordinate = proxy.convert(location, from: .local) else { return }
                    tapped(coordinate)
                }
            }
            if let callout {
                TrackCalloutCard(callout: callout) { self.callout = nil }
            }
            MapLegendView(detail: detail, effort: effort)
            if !detail.timeline.isEmpty {
                Text("Tap the track to move the replay playhead — on a mark or a flight for "
                     + "what it was.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        #if DEBUG && targetEnvironment(simulator)
        .onAppear(perform: stageCalloutForScreenshot)
        #endif
    }

    /// One tap, three answers, in order of how specific they are.
    ///
    /// A tap that lands on a *mark* means that mark — the tolerance is tight, so it takes
    /// aim rather than a stray press near it. Otherwise the tap moves the playhead, which is
    /// what the caption promises; and when it landed on a stretch of *flown* track it also
    /// says which flight that was and frames the flight in the chart. A tap nowhere near the
    /// track is ignored rather than snapping the playhead to some unrelated corner of the
    /// session. Both tolerances scale with how much water the map is showing, so they are
    /// roughly a fingertip at any zoom.
    private func tapped(_ coordinate: CLLocationCoordinate2D) {
        let spanM = detail.region.span.latitudeDelta * 110_540
        if let mark = detail.mark(nearLat: coordinate.latitude, lon: coordinate.longitude,
                                  toleranceM: max(12, spanM * 0.025)) {
            callout = mark
            playhead = mark.t
            return
        }
        guard let t = detail.time(nearLat: coordinate.latitude, lon: coordinate.longitude,
                                  toleranceM: max(25, spanM * 0.06)) else { return }
        playhead = t
        // Off the foil a tap is a scrub and nothing more: there is no flight to name, and a
        // callout that said so would be noise on every second press.
        if let flight = detail.flightCallout(at: t) {
            callout = flight
            focus(on: flight)
        } else {
            callout = nil
        }
    }

    /// Ask the chart to frame the flight this callout is about.
    private func focus(on callout: SessionDetail.Callout) {
        guard let span = callout.focus else { return }
        focusTick += 1
        flightFocus = SessionDetail.FlightFocus(span: span, tick: focusTick)
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Screenshot hook, same family as `UI_HIDE_LAYERS`: the pairing is tap-only and
    /// `simctl` has no fingers, so `UI_MAP_CALLOUT=takeoff|failed|end|flight` opens the
    /// first callout of that kind. Staging only — it opens the same card a tap opens.
    private func stageCalloutForScreenshot() {
        guard let kind = ProcessInfo.processInfo.environment["UI_MAP_CALLOUT"] else { return }
        switch kind {
        case "takeoff", "failed":
            let wantFailed = kind == "failed"
            guard let mark = detail.takeoffMarks.first(where: { $0.isFailed == wantFailed })
            else { return }
            callout = SessionDetail.Callout(id: "takeoff-\(mark.id)", title: mark.title,
                                            detail: mark.detail, pairing: mark.pairing,
                                            t: mark.t)
            playhead = mark.t
        case "end":
            guard let marker = detail.markers.first(where: { $0.pairing != nil }) else { return }
            callout = SessionDetail.Callout(id: "marker-\(marker.id)", title: marker.title,
                                            detail: marker.detail, pairing: marker.pairing,
                                            t: marker.t)
            playhead = marker.t
        case "flight":
            guard let flight = detail.pairings.first else { return }
            let middle = (flight.startTs + flight.endTs) / 2
            callout = detail.flightCallout(at: middle)
            playhead = middle
            if let callout { focus(on: callout) }
        default: return
        }
    }
    #endif
}

/// The tap-only callout, under the map rather than over it: the answer to "what is this?"
/// must not cover the thing that was tapped, and a card that stays put while the rider looks
/// back at the track beats a popover they have to dismiss to see anything.
private struct TrackCalloutCard: View {
    let callout: SessionDetail.Callout
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(callout.title).font(.footnote.weight(.semibold))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Text(callout.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
            // The line this whole feature is for. Absent — not blank — on a mark that is
            // not a flight boundary.
            if let pairing = callout.pairing {
                Text(pairing)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("pairing-line")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}

struct FullScreenMapView: View {
    let detail: SessionDetail
    let effort: SessionDetail.RecordEffort?
    var playheadT: Double?

    /// Read here rather than passed in: this view is pushed, so it has to observe the
    /// shared model itself to redraw when a chip is tapped *on this screen*.
    @Environment(SessionStore.self) private var store

    @State private var direction = DirectionField()

    var body: some View {
        Map(initialPosition: .region(detail.initialRegion)) {
            TrackContent(detail: detail, effort: effort, visibility: store.mapLayers,
                         playhead: playheadT.flatMap(detail.moment),
                         direction: direction)
        }
        .mapStyle(.standard(elevation: .flat))
        // The big map pans, zooms *and rotates*, and all three change the answer: how far
        // apart the chevrons should be, which of them are on screen, and which way "north"
        // points on the glyph.
        .onMapCameraChange(frequency: .onEnd) { context in
            direction.camera(moved: context, detail: detail)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            direction.resized(to: size, detail: detail)
        }
        .navigationTitle(SessionDisplay.title(detail.row))
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .bottom)
        // The same chips, over the same model: filtering the big map is exactly where a
        // rider wants it, and a second copy of the state would be the way to make the two
        // maps disagree.
        .safeAreaInset(edge: .bottom) {
            MapLegendView(detail: detail, effort: effort, compact: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial)
        }
    }
}

/// Shared map content so the inline and full-screen maps never drift apart.
private struct TrackContent: MapContent {
    let detail: SessionDetail
    let effort: SessionDetail.RecordEffort?
    let visibility: MapLayerVisibility
    let playhead: SessionDetail.TimelinePoint?
    let direction: DirectionField

    var body: some MapContent {
        ForEach(detail.segments) { segment in
            let style = visibility.lineStyle(flying: segment.flying)
            MapPolyline(coordinates: segment.points.map(Self.coordinate))
                .stroke(Self.color(style),
                        style: StrokeStyle(lineWidth: Self.width(style),
                                           lineCap: .round, lineJoin: .round))
        }
        // Under the effort glow and under the markers: a pumping attempt is context for
        // the takeoff (or the failure) that ends it, not a thing to read on its own.
        if visibility.isVisible(.pumping) {
            // An attempt the GPS had no fix for is counted by the legend and drawn by
            // nobody: a one-point polyline is not a stretch of water.
            ForEach(detail.pumpSpans.filter { $0.points.count >= 2 }) { span in
                MapPolyline(coordinates: span.points.map(Self.coordinate))
                    .stroke(EventMarkerStyle.pumping.opacity(0.75),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round,
                                               lineJoin: .round))
            }
        }
        // Above the route, below everything that marks an *event*: the chevrons are meant to
        // be read as a property of the line — which way it goes — not as things that happened.
        if visibility.isVisible(.direction) {
            ForEach(direction.chevrons) { chevron in
                Annotation("", coordinate: Self.coordinate(chevron.lat, chevron.lon),
                           anchor: .center) {
                    DirectionChevron(bearingDeg: chevron.bearingDeg - direction.headingDeg,
                                     style: visibility.lineStyle(flying: chevron.flying))
                }
                .annotationTitles(.hidden)
            }
        }
        // The record effort glows over the phase colouring: provenance the engine already
        // computed (`records.windows`), so the rider can see *where* the best run happened.
        if let effort, effort.points.count >= 2, visibility.isVisible(.effort) {
            MapPolyline(coordinates: effort.points.map(Self.coordinate))
                .stroke(DesignTokens.Effort.window,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        }
        if visibility.isVisible(.takeoff) {
            ForEach(detail.takeoffMarks) { mark in
                Annotation("", coordinate: Self.coordinate(mark.lat, mark.lon),
                           anchor: .center) {
                    EventMarkerStyle.takeoffMark(mark)
                        .accessibilityLabel("\(mark.title), \(mark.detail)")
                }
                .annotationTitles(.hidden)
            }
        }
        if visibility.isVisible(.splash) {
            ForEach(detail.splashMarks) { mark in
                Annotation("", coordinate: Self.coordinate(mark.lat, mark.lon),
                           anchor: .center) {
                    EventMarkerStyle.splashMark()
                        .accessibilityLabel("\(mark.title), \(mark.detail)")
                }
                .annotationTitles(.hidden)
            }
        }
        ForEach(detail.visibleMarkers(visibility)) { marker in
            Annotation("", coordinate: Self.coordinate(marker.lat, marker.lon),
                       anchor: .center) {
                EventMarkerStyle.dot(marker)
                    .accessibilityLabel("\(marker.title), \(marker.detail)")
            }
            .annotationTitles(.hidden)
        }
        // Drawn last so it sits above the outcome dots — it is the thing being moved.
        if let playhead, let lat = playhead.lat, let lon = playhead.lon {
            Annotation("", coordinate: Self.coordinate(lat, lon), anchor: .center) {
                PlayheadDot(flying: playhead.flying)
                    .accessibilityLabel(String(format: "Replay position, %.1f knots",
                                               playhead.kn))
            }
            .annotationTitles(.hidden)
        }
    }

    /// A hidden *line* category keeps its route as a thin neutral line: the chips filter
    /// what the colours claim, not where the rider went. Losing the track to a legend tap
    /// would be a much worse surprise than an unwanted tint.
    private static func color(_ style: TrackLineStyle) -> Color {
        switch style {
        case .flying: return DesignTokens.Phase.flying
        case .offFoil: return DesignTokens.Phase.offFoil.opacity(0.65)
        case .neutral: return DesignTokens.Phase.offFoil.opacity(0.3)
        }
    }

    private static func width(_ style: TrackLineStyle) -> CGFloat {
        switch style {
        case .flying: return 4
        case .offFoil: return 2
        case .neutral: return 1.5
        }
    }

    private static func coordinate(_ point: SessionDetail.Point) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
    }

    private static func coordinate(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// One direction mark. Small, semi-transparent and tinted like the water under it, because
/// it has to lose every contest with the event dots: an arrow is texture on the line, and a
/// touchdown is news.
///
/// Rotation is course *minus the camera's heading*, so it keeps pointing where he was going
/// after the rider spins the big map. Hidden from VoiceOver on purpose — a hundred elements
/// reading "chevron" is noise, and the legend chip is where the layer is named.
private struct DirectionChevron: View {
    let bearingDeg: Double
    let style: TrackLineStyle

    var body: some View {
        Image(systemName: "chevron.up")
            // Semibold at 8pt rather than bold at 9: at bold the run of arrows read as a
            // second dotted line competing with the track, which is precisely the thing a
            // direction hint must not do.
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(tint)
            .rotationEffect(.degrees(bearingDeg))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private extension DirectionChevron {
    /// Mixed towards the label colour rather than simply tinted: a teal arrow drawn on the
    /// teal flying track would be invisible, and this stays phase-coloured while separating
    /// from the line in both light and dark mode.
    var tint: Color {
        switch style {
        case .flying:
            return DesignTokens.Phase.flying.mix(with: Color(.label), by: 0.55).opacity(0.62)
        case .offFoil: return Color(.label).opacity(0.38)
        case .neutral: return Color(.label).opacity(0.22)
        }
    }
}

/// The chevron set as it stands for the current camera, and the heading it was built for.
///
/// Kept as a value the two maps each own a copy of: the spacing is in screen points, so the
/// answer depends on the camera and the view size, and both change independently on the
/// full-screen map. Rebuilding is a walk over the track — cheap enough to do on every camera
/// *end*, which is why the frequency is `.onEnd` rather than continuous.
struct DirectionField {
    private(set) var chevrons: [TrackDirection.Chevron] = []
    private(set) var headingDeg: Double = 0
    private var region: MKCoordinateRegion?
    private var size: CGSize = .zero

    mutating func camera(moved context: MapCameraUpdateContext, detail: SessionDetail) {
        region = context.region
        headingDeg = context.camera.heading
        rebuild(detail)
    }

    mutating func resized(to size: CGSize, detail: SessionDetail) {
        guard size != self.size else { return }
        self.size = size
        // The inline map never moves its camera, so a layout pass is the only moment it ever
        // gets to build its chevrons.
        if region == nil { region = detail.initialRegion }
        rebuild(detail)
    }

    private mutating func rebuild(_ detail: SessionDetail) {
        guard let region, size.width > 0, size.height > 0 else {
            chevrons = []
            return
        }
        let span = region.span
        let scale = TrackDirection.metresPerPoint(latSpan: span.latitudeDelta,
                                                  lonSpan: span.longitudeDelta,
                                                  centerLat: region.center.latitude,
                                                  widthPoints: size.width,
                                                  heightPoints: size.height)
        let box = TrackDirection.Box(centerLat: region.center.latitude,
                                     centerLon: region.center.longitude,
                                     latSpan: span.latitudeDelta,
                                     lonSpan: span.longitudeDelta)
        chevrons = TrackDirection.chevrons(along: detail.directionPoints,
                                           metresPerPoint: scale, within: box)
    }
}

/// The replay marker: deliberately unlike the outcome dots (bigger, white-ringed, with a
/// halo) so it reads as "where you are now" rather than "something happened here".
private struct PlayheadDot: View {
    let flying: Bool

    var body: some View {
        let tint = flying ? DesignTokens.Phase.flying : DesignTokens.Phase.offFoil
        ZStack {
            Circle().fill(tint.opacity(0.28)).frame(width: 28, height: 28)
            Circle()
                .fill(tint)
                .stroke(.white, lineWidth: 2.5)
                .frame(width: 15, height: 15)
        }
        .shadow(radius: 2)
    }
}

extension SessionDetail {
    var region: MKCoordinateRegion {
        guard let bounds else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 45.87,
                                                                     longitude: 10.87),
                                      span: MKCoordinateSpan(latitudeDelta: 0.05,
                                                             longitudeDelta: 0.05))
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: bounds.centerLat, longitude: bounds.centerLon),
            span: MKCoordinateSpan(latitudeDelta: bounds.latSpan, longitudeDelta: bounds.lonSpan))
    }

    /// The camera both maps open on. Identical to `region` in a shipping build; the debug
    /// hook exists because the chevron spacing is a function of the zoom, and `simctl` has
    /// no fingers to pinch a second scale into existence.
    var initialRegion: MKCoordinateRegion {
        #if DEBUG && targetEnvironment(simulator)
        // `UI_MAP_ZOOM=<factor>` tightens the camera by that factor around the same centre.
        if let factor = ProcessInfo.processInfo.environment["UI_MAP_ZOOM"]
            .flatMap(Double.init), factor > 1 {
            let region = self.region
            return MKCoordinateRegion(
                center: region.center,
                span: MKCoordinateSpan(latitudeDelta: region.span.latitudeDelta / factor,
                                       longitudeDelta: region.span.longitudeDelta / factor))
        }
        #endif
        return region
    }

    /// The track as one polyline with the phase carried per point — the input the chevron
    /// decimation walks. Flattened rather than fed segment by segment: spacing has to be
    /// continuous across a takeoff, or every short off-foil run would collect its own
    /// cluster of arrows.
    var directionPoints: [TrackDirection.Point] {
        segments.flatMap { segment in
            segment.points.map {
                TrackDirection.Point(lat: $0.lat, lon: $0.lon, flying: segment.flying)
            }
        }
    }
}
