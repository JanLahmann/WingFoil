import CoreLocation
import MapKit
import SwiftUI

/// Track drawn as segmented polylines coloured by phase (flying vs everything else), with
/// the maneuver/flight-end outcomes marked and one GP3S effort highlighted. The inline map
/// is non-interactive so the detail page scrolls; the full-screen version is interactive.
struct TrackMapView: View {
    let detail: SessionDetail
    /// The GP3S effort whose window is glowing on the track, if any.
    let effort: SessionDetail.RecordEffort?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Map(initialPosition: .region(detail.region), interactionModes: []) {
                TrackContent(detail: detail, effort: effort)
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .frame(height: 260)
            .clipShape(.rect(cornerRadius: 14))
            legend
            if !detail.markers.isEmpty {
                EventMarkerStyle.legend()
                Text("Solid = maneuver outcome · hollow = straight-line flight end")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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

    var body: some View {
        Map(initialPosition: .region(detail.region)) {
            TrackContent(detail: detail, effort: effort)
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
    }

    private static func coordinate(_ point: SessionDetail.Point) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
    }

    private static func coordinate(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
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
