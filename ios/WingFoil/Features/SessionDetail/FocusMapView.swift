import CoreLocation
import MapKit
import SwiftUI
import WingFoilKit

/// **The analysis maps' shared frame** — the Turns tab's and the Takeoffs tab's.
///
/// Both pages ask the same shape of question: *here is a filtered set of things that
/// happened; where were they?* So both draw the same picture — the whole session's track
/// receding into the background, the page's own marks on top of it, one of them enlarged
/// because the reader tapped its row — and both control it the same way, with the legend
/// every other map on the page uses.
///
/// It exists because the Turns map was written first and the Takeoffs map would have been a
/// copy of it. Everything that is genuinely shared is here: the neutral route and its halo
/// over photography, the direction chevrons and their camera bookkeeping, the pan/zoom
/// interaction set, the figure height and corner, the caption line, and the legend. What is
/// *not* here is the marks — those are the page's subject, and each page passes its own in.
///
/// **The ground and the layers are the map's, the filter is the page's.** The style picker
/// and the layer chips live in the legend below (`MapLegendView`, given this map's
/// `MapLayerScope`); the type/side segments on Turns and the outcome chips on Takeoffs are a
/// different control answering a different question, and they stay above, with the tally
/// they move.
struct FocusMapView<Marks: MapContent>: View {
    let detail: SessionDetail
    /// Which map this is: it decides the legend's chips and which stored visibility set the
    /// drawing reads.
    let scope: MapLayerScope
    /// The line under the figure — how many marks survived the page's filter, and what to do
    /// next. Written by the page, because only the page knows what it is counting.
    let caption: String
    /// The page's own marks, drawn over the route in the order given: spans first, then
    /// pins, then whatever is focused.
    @MapContentBuilder var marks: () -> Marks

    /// Read here rather than passed in: the ground (`MapStyleChoice`) and this map's layer
    /// set are both shared model, and this view is one of the surfaces that must redraw when
    /// a chip is tapped on it.
    @Environment(SessionStore.self) private var store

    /// The chevrons for the camera as it stands — a function of the zoom and the view size,
    /// so it is rebuilt on every camera settle exactly as the session map does it.
    @State private var direction = DirectionField()

    private var visibility: MapLayerVisibility { store.mapLayers(for: scope) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Map(initialPosition: .region(detail.initialRegion),
                interactionModes: [.zoom, .pan]) {
                route
                // Above the route, below every mark: the arrows are a property of the line —
                // which way it goes — not things that happened.
                if visibility.isVisible(.direction) {
                    ForEach(direction.chevrons) { chevron in
                        Annotation("", coordinate: CLLocationCoordinate2D(
                            latitude: chevron.lat, longitude: chevron.lon), anchor: .center) {
                            TrackHalo.around(
                                DirectionChevron(bearingDeg: chevron.bearingDeg
                                                     - direction.headingDeg,
                                                 style: .neutral, ground: store.mapStyle),
                                on: store.mapStyle)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                marks()
            }
            .mapStyle(store.mapStyle.mapStyle)
            .figureHeight(regular: 240, compact: 180)
            .clipShape(.rect(cornerRadius: 14))
            .onMapCameraChange(frequency: .onEnd) { context in
                direction.camera(moved: context, detail: detail)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                direction.resized(to: size, detail: detail)
            }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            // The same control every map on this page has, over this map's own set. The lone
            // style chip that used to sit in the caption line is inside it now — the ground
            // was never the only thing about this map worth changing, it was only the only
            // one that had a control.
            MapLegendView(detail: detail, effort: nil, scope: scope)
        }
    }

    /// The session's whole track, receding.
    ///
    /// Deliberately neutral on both analysis maps: the page is about one filtered subset,
    /// and a phase-tinted track under it would be the loudest thing on a 240 pt figure. Over
    /// photography "recede" said in the app's own ink recedes all the way out of sight, so
    /// the route gets the same dark outer edge and the same flipped ink the session map's
    /// track gets, from the same place (`TrackHalo`).
    @MapContentBuilder
    private var route: some MapContent {
        if store.mapStyle.isImagery {
            ForEach(detail.segments) { segment in
                MapPolyline(coordinates: segment.points.map(Self.coordinate))
                    .stroke(TrackHalo.ink,
                            style: StrokeStyle(
                                lineWidth: TrackHalo.width(under: segment.flying ? 3 : 1.5),
                                lineCap: .round, lineJoin: .round))
            }
        }
        ForEach(detail.segments) { segment in
            MapPolyline(coordinates: segment.points.map(Self.coordinate))
                .stroke(TrackHalo.ink(Color.secondary, on: store.mapStyle,
                                      opacity: segment.flying ? 0.45 : 0.22,
                                      overImagery: segment.flying ? 0.8 : 0.45),
                        style: StrokeStyle(lineWidth: segment.flying ? 3 : 1.5,
                                           lineCap: .round, lineJoin: .round))
        }
    }

    private static func coordinate(_ point: SessionDetail.Point) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
    }
}

extension SessionDetail.Point {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
