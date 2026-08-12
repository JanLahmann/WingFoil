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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MapReader { proxy in
                Map(initialPosition: .region(detail.region), interactionModes: []) {
                    TrackContent(detail: detail, effort: effort,
                                 visibility: visibility,
                                 playhead: playhead.flatMap(detail.moment))
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 260)
                .clipShape(.rect(cornerRadius: 14))
                // Interaction is off so the page scrolls, which leaves the tap free to
                // mean exactly one thing: "show me this point".
                .onTapGesture { location in
                    guard let coordinate = proxy.convert(location, from: .local) else { return }
                    scrub(to: coordinate)
                }
            }
            MapLegendView(detail: detail, effort: effort)
            if !detail.timeline.isEmpty {
                Text("Tap the track to move the replay playhead.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// A tap that lands nowhere near the track is ignored rather than snapping the playhead
    /// to some unrelated corner of the session. The tolerance scales with how much water
    /// the map is showing, so it is roughly a fingertip at any zoom.
    private func scrub(to coordinate: CLLocationCoordinate2D) {
        let spanM = detail.region.span.latitudeDelta * 110_540
        let tolerance = max(25, spanM * 0.06)
        if let t = detail.time(nearLat: coordinate.latitude, lon: coordinate.longitude,
                               toleranceM: tolerance) {
            playhead = t
        }
    }

}

struct FullScreenMapView: View {
    let detail: SessionDetail
    let effort: SessionDetail.RecordEffort?
    var playheadT: Double?

    /// Read here rather than passed in: this view is pushed, so it has to observe the
    /// shared model itself to redraw when a chip is tapped *on this screen*.
    @Environment(SessionStore.self) private var store

    var body: some View {
        Map(initialPosition: .region(detail.region)) {
            TrackContent(detail: detail, effort: effort, visibility: store.mapLayers,
                         playhead: playheadT.flatMap(detail.moment))
        }
        .mapStyle(.standard(elevation: .flat))
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

    var body: some MapContent {
        ForEach(detail.segments) { segment in
            let style = visibility.lineStyle(flying: segment.flying)
            MapPolyline(coordinates: segment.points.map(Self.coordinate))
                .stroke(Self.color(style),
                        style: StrokeStyle(lineWidth: Self.width(style),
                                           lineCap: .round, lineJoin: .round))
        }
        // The record effort glows over the phase colouring: provenance the engine already
        // computed (`records.windows`), so the rider can see *where* the best run happened.
        if let effort, effort.points.count >= 2, visibility.isVisible(.effort) {
            MapPolyline(coordinates: effort.points.map(Self.coordinate))
                .stroke(Color.orange,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
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
        case .flying: return .teal
        case .offFoil: return Color.secondary.opacity(0.65)
        case .neutral: return Color.secondary.opacity(0.3)
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

/// The replay marker: deliberately unlike the outcome dots (bigger, white-ringed, with a
/// halo) so it reads as "where you are now" rather than "something happened here".
private struct PlayheadDot: View {
    let flying: Bool

    var body: some View {
        let tint = flying ? Color.teal : Color.secondary
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
}
