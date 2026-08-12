import CoreLocation
import MapKit
import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MapReader { proxy in
                Map(initialPosition: .region(detail.region), interactionModes: []) {
                    TrackContent(detail: detail, effort: effort,
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
            legend
            if !detail.markers.isEmpty {
                EventMarkerStyle.legend()
                Text("Solid = maneuver outcome · hollow = straight-line flight end")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: .teal, label: "flying")
            legendItem(color: .secondary, label: "off foil")
            if let effort {
                legendItem(color: .orange, label: effort.label.lowercased())
            }
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 16, height: 4)
            Text(label)
        }
    }
}

struct FullScreenMapView: View {
    let detail: SessionDetail
    let effort: SessionDetail.RecordEffort?
    var playheadT: Double?

    var body: some View {
        Map(initialPosition: .region(detail.region)) {
            TrackContent(detail: detail, effort: effort,
                         playhead: playheadT.flatMap(detail.moment))
        }
        .mapStyle(.standard(elevation: .flat))
        .navigationTitle(SessionDisplay.title(detail.row))
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .bottom)
    }
}

/// Shared map content so the inline and full-screen maps never drift apart.
private struct TrackContent: MapContent {
    let detail: SessionDetail
    let effort: SessionDetail.RecordEffort?
    let playhead: SessionDetail.TimelinePoint?

    var body: some MapContent {
        ForEach(detail.segments) { segment in
            MapPolyline(coordinates: segment.points.map(Self.coordinate))
                .stroke(segment.flying ? Color.teal : Color.secondary.opacity(0.65),
                        style: StrokeStyle(lineWidth: segment.flying ? 4 : 2,
                                           lineCap: .round, lineJoin: .round))
        }
        // The record effort glows over the phase colouring: provenance the engine already
        // computed (`records.windows`), so the rider can see *where* the best run happened.
        if let effort, effort.points.count >= 2 {
            MapPolyline(coordinates: effort.points.map(Self.coordinate))
                .stroke(Color.orange,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        }
        ForEach(detail.markers) { marker in
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
