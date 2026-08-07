import CoreLocation
import MapKit
import SwiftUI

/// Track drawn as segmented polylines coloured by phase: flying (from the analysis
/// flight ranges) vs everything else. The inline map is non-interactive so the detail
/// page scrolls; the full-screen version is fully interactive.
struct TrackMapView: View {
    let detail: SessionDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Map(initialPosition: .region(detail.region), interactionModes: []) {
                TrackContent(detail: detail)
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .frame(height: 260)
            .clipShape(.rect(cornerRadius: 14))
            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: .teal, label: "flying")
            legendItem(color: .secondary, label: "off foil")
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

    var body: some View {
        Map(initialPosition: .region(detail.region)) {
            TrackContent(detail: detail)
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

    var body: some MapContent {
        ForEach(detail.segments) { segment in
            MapPolyline(coordinates: segment.points.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
            })
            .stroke(segment.flying ? Color.teal : Color.secondary.opacity(0.65),
                    style: StrokeStyle(lineWidth: segment.flying ? 4 : 2,
                                       lineCap: .round, lineJoin: .round))
        }
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
