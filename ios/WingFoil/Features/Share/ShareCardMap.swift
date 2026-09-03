import CoreLocation
import MapKit
import SwiftUI
import WingFoilKit

/// The share card's optional map background: one `MKMapSnapshotter` image, and the track
/// re-placed onto it.
///
/// The iOS twin of `web/js/cardmap.js`, which composites OpenStreetMap tiles for the same
/// picture. Both exist for one reason: a card that shows *where* the session was is a
/// different message from a card that shows only its shape, and a rider posting into a group
/// chat is usually answering "where were you".
///
/// **Off by default, and nothing here runs until it is asked for** (`ShareCardMapStore`). The
/// plain card must stay the card this app has always exported.
///
/// **The projection is the map's, not the card's.** `TrackOutlineView` normally fits the ride
/// to its box through `TrackThumbnail`'s unit square — a projection about the *session*, which
/// has no idea where the water is. With a map behind it the breadcrumb has to sit on the earth
/// the snapshot is a picture of, so every vertex is put through `MKMapSnapshot.point(for:)`
/// and carried to the card as a plain `CGPoint`. Nothing downstream needs MapKit.
///
/// **And the ride lands where it always did.** The snapshot is framed so the track fills
/// exactly the rectangle the card's layout gave it — the map is simply what the card's
/// remaining margins now show. A rider flipping the switch sees one card with and without
/// ground under it, not two cards.
struct ShareCardMap: Equatable {

    /// One phase run, already in the card's own points.
    struct Run: Equatable {
        var flying: Bool
        var points: [CGPoint]
    }

    /// One marker, already in the card's own points.
    struct Mark: Equatable {
        var point: CGPoint
        var kind: TrackThumbnail.Mark.Kind
    }

    var image: UIImage
    var runs: [Run]
    var marks: [Mark]
    /// How faint the breadcrumb is drawn. 1 for a session — one ride, at full strength — and
    /// `TrackStack.opacity` for a period, where a dozen outlines have to read as one shape
    /// rather than as a scribble. The runs of every session in the stack are in this one list,
    /// which is exactly what the web does with `globalAlpha`: one alpha, every stroke.
    var opacity: Double = 1
    /// The flying line's width in layout points — 2.6 for a session, and the stack's thinner
    /// 1.8 for a period, so a mapped stack is the plain stack with ground under it rather than
    /// a second, heavier picture. Off-foil legs are half of it, as everywhere else.
    var lineWidth: Double = 2.6
    /// Whether the ground is photography, and the track therefore needs its dark outer halo —
    /// the same rule the session maps draw by (`MapStyleRecipe.needsTrackHalo`).
    var needsHalo: Bool

    /// The credit the card prints in its corner.
    ///
    /// `MKMapSnapshotter` does burn Apple's own attribution into the bottom-left of the image,
    /// but on this card that corner is the brand mark and the call to action — so the burnt-in
    /// one comes out half-covered, which is worse than not showing it at all. It is cropped
    /// away (`ShareCardMapper.attributionBand`) and replaced by this, set where nothing else on
    /// the card goes. Kept to the shortest form that names the source, because it has to sit in
    /// the corner of a picture whose whole job is to be about the ride.
    static let credit = "Maps © Apple"

    static func == (a: ShareCardMap, b: ShareCardMap) -> Bool {
        a.image === b.image && a.runs == b.runs && a.marks == b.marks
            && a.needsHalo == b.needsHalo && a.opacity == b.opacity
            && a.lineWidth == b.lineWidth
    }
}

/// A coordinate the card wants on the map, before anything has been projected.
struct ShareCardMapSource {
    struct Point {
        var lat: Double
        var lon: Double
        var flying: Bool
    }

    struct Mark {
        var lat: Double
        var lon: Double
        var kind: TrackThumbnail.Mark.Kind
    }

    var points: [Point]
    var marks: [Mark]

    var isEmpty: Bool { points.count < 2 }
}

extension ShareCardMapSource {

    /// A cached outline put back on the earth — one afternoon of a period card's ground.
    ///
    /// The thumbnail's `bounds` is what makes this possible at all: `Point` is a session
    /// normalized against itself, and the anchor it was projected around is the only way back.
    /// nil for a thumbnail without one (a v2 blob the cache has not rebuilt, or a recording
    /// with no positions), which quietly keeps that afternoon off the map rather than putting
    /// it in the wrong bay.
    ///
    /// No marks: the stack draws none, because fifty outcome dots per session times a dozen
    /// sessions is confetti and the card's own numbers already say how the maneuvers went.
    init?(thumbnail: TrackThumbnail) {
        guard thumbnail.bounds != nil else { return nil }
        let placed = thumbnail.points.compactMap { point -> Point? in
            guard let c = thumbnail.coordinate(x: point.x, y: point.y) else { return nil }
            return Point(lat: c.lat, lon: c.lon, flying: point.flying)
        }
        guard placed.count >= 2 else { return nil }
        self.init(points: placed, marks: [])
    }
}

enum ShareCardMapper {

    /// The inset the card's track box reserves — `TrackOutlineView`'s padding plus the mark
    /// radius the share card asks it for, because a dot on the outermost vertex is centred
    /// *on* the fitted edge. The framing has to reserve exactly the same margin or a mapped
    /// track would come out a different size from a plain one. One number in the kit, four
    /// readers (`ShareCardStats.trackInset`); twin of `TRACK_INSET` in web/js/sharecard.js.
    static let inset = ShareCardStats.trackInset

    /// What a session with no extent at all is given instead of a fit: a rider who never
    /// moved gets his launch beach and its shoreline rather than a division by zero.
    static let degenerateSpanM: Double = 600

    /// The strip of snapshot the card asks for and then throws away.
    ///
    /// `MKMapSnapshotter` burns Apple's own "Maps" attribution into the bottom-left of every
    /// image it returns — which on this card lands exactly under the brand mark and the call
    /// to action, where it reads as a smudge and is half-covered, which is worse than not
    /// showing it. So the snapshot is taken a band taller than the card and pinned to the
    /// card's top edge, and the credit is printed instead as `ShareCardMap.credit`, in a
    /// corner nothing else uses and nothing ever covers.
    ///
    /// Cropping costs nothing in accuracy: the extra height is added to the *bottom* of the
    /// map rect, so the origin, the scale and therefore every projected point are untouched —
    /// `MKMapSnapshot.point(for:)` still answers in the image's own coordinates, and the
    /// image's top-left is the card's top-left — and it is free, because the scale comes from
    /// the track box, not from the height: a taller snapshot is more map fetched and thrown
    /// away, never a different zoom. Forty-four points is comfortably past the tallest badge
    /// MapKit has drawn, with room for it to grow.
    static let attributionBand: CGFloat = 44

    /// Snapshot the ground under one card, and place the track on it.
    ///
    /// `size` is the card in layout points (its exported pixels over `renderScale`) and
    /// `trackBox` the rectangle the card's own layout handed the ride, measured from the live
    /// view rather than recomputed here — see `ShareCardView.onTrackFrame`.
    ///
    /// nil for every failure, and the caller's answer to all of them is the same: draw the
    /// plain card. A rider in a tunnel still gets a card.
    static func make(source: ShareCardMapSource, size: CGSize, trackBox: CGRect,
                     style: MapStyleChoice) async -> ShareCardMap? {
        await make(sources: [source], size: size, trackBox: trackBox, style: style)
    }

    /// The same, for a **period**: many outlines on one ground.
    ///
    /// One snapshot, framed on the union of every session's bounding box, and every session's
    /// breadcrumb projected onto it. The switch is only offered where that union is a beach
    /// rather than a county (`Period.mapGround`), which is what makes one framing honest for a
    /// dozen afternoons.
    ///
    /// The runs of all of them come back in one list at one `opacity`, because that is what
    /// the picture is: an accumulation, drawn faint, in which the water everything was ridden
    /// over comes out brightest.
    static func makeStack(sources: [ShareCardMapSource], size: CGSize, trackBox: CGRect,
                          style: MapStyleChoice) async -> ShareCardMap? {
        await make(sources: sources, size: size, trackBox: trackBox, style: style,
                   opacity: TrackStack.opacity(count: sources.count), lineWidth: 1.8)
    }

    static func make(sources: [ShareCardMapSource], size: CGSize, trackBox: CGRect,
                     style: MapStyleChoice, opacity: Double = 1,
                     lineWidth: Double = 2.6) async -> ShareCardMap? {
        let usable = sources.filter { !$0.isEmpty }
        guard !usable.isEmpty, size.width > 0, size.height > 0,
              trackBox.width > 1, trackBox.height > 1,
              let rect = frame(sources: usable, size: size, trackBox: trackBox) else {
            return nil
        }

        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.size = CGSize(width: size.width, height: size.height + attributionBand)
        // Always the light map, never the reader's own appearance setting. A card is a fixed
        // artefact: the same session exported from two phones has to be the same picture, and
        // Apple's dark map under a scrim heavy enough to carry white text is a black
        // rectangle — the coastline, which is the whole reason the switch exists, disappears.
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        options.preferredConfiguration = style.recipe.snapshotConfiguration
        options.showsBuildings = false

        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start() else { return nil }

        var runs: [ShareCardMap.Run] = []
        var marks: [ShareCardMap.Mark] = []
        for source in usable {
            var current: [CGPoint] = []
            var flying = source.points[1].flying
            for point in source.points {
                let placed = snapshot.point(for: CLLocationCoordinate2D(latitude: point.lat,
                                                                       longitude: point.lon))
                if point.flying != flying, !current.isEmpty {
                    // Consecutive runs share a vertex, so the polyline has no visual gap where
                    // the phase changes — the same rule `TrackThumbnail.runs` draws by.
                    current.append(placed)
                    if current.count >= 2 {
                        runs.append(.init(flying: flying, points: current))
                    }
                    current = [placed]
                    flying = point.flying
                } else {
                    current.append(placed)
                }
            }
            if current.count >= 2 { runs.append(.init(flying: flying, points: current)) }

            marks.append(contentsOf: source.marks.map { mark in
                ShareCardMap.Mark(
                    point: snapshot.point(for: CLLocationCoordinate2D(latitude: mark.lat,
                                                                      longitude: mark.lon)),
                    kind: mark.kind)
            })
        }
        return ShareCardMap(image: snapshot.image, runs: runs, marks: marks,
                            opacity: opacity, lineWidth: lineWidth,
                            needsHalo: style.recipe.needsTrackHalo)
    }

    /// The piece of the world the card shows, chosen so the ride fills `trackBox` exactly.
    ///
    /// Uniform in both axes, like every other fit on this card: a track stretched to fill two
    /// axes is a different-shaped session, and a *map* stretched to fill two axes is a lie
    /// about the coastline.
    static func frame(source: ShareCardMapSource, size: CGSize,
                      trackBox: CGRect) -> MKMapRect? {
        frame(sources: [source], size: size, trackBox: trackBox)
    }

    /// The union of every source's bounding box, fitted to the track slot — one session's for
    /// a session card, a whole period's for a period card.
    static func frame(sources: [ShareCardMapSource], size: CGSize,
                      trackBox: CGRect) -> MKMapRect? {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        func absorb(_ lat: Double, _ lon: Double) {
            let p = MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        for source in sources {
            for point in source.points { absorb(point.lat, point.lon) }
            // The marks count: one is placed from the sample nearest its instant and can sit a
            // hair outside the polyline, and a frame that ignored it would push the dot off
            // the edge of an exported image.
            for mark in source.marks { absorb(mark.lat, mark.lon) }
        }
        guard minX.isFinite, maxX > -Double.infinity else { return nil }

        let width = max(trackBox.width - inset * 2, 1)
        let height = max(trackBox.height - inset * 2, 1)
        let dx = maxX - minX, dy = maxY - minY
        // Map points per layout point. A perfectly straight leg has zero extent on one axis;
        // that axis then imposes no limit, which is exactly right — `max` takes the other.
        var scale = max(dx > 0 ? dx / width : 0, dy > 0 ? dy / height : 0)
        if scale <= 0 {
            let centre = MKMapPoint(x: minX, y: minY).coordinate
            let perMetre = MKMapPointsPerMeterAtLatitude(centre.latitude)
            scale = perMetre * degenerateSpanM / max(trackBox.width, 1)
        }
        guard scale > 0, scale.isFinite else { return nil }

        let centreX = (minX + maxX) / 2, centreY = (minY + maxY) / 2
        // The band is added to the bottom only, so the origin — and with it every projected
        // point — is exactly what a card-sized snapshot would have produced.
        return MKMapRect(x: centreX - trackBox.midX * scale,
                         y: centreY - trackBox.midY * scale,
                         width: size.width * scale,
                         height: (size.height + attributionBand) * scale)
    }
}

extension MapStyleRecipe {

    /// What this recipe asks a *snapshotter* for. The twin of `MapStyleChoice.mapStyle`
    /// (`MapStylePicker.swift`), which answers the same question for a live `Map`: one table
    /// in the kit, two renderers, so a rider who switched the session map to satellite gets a
    /// satellite card without being asked a second time.
    var snapshotConfiguration: MKMapConfiguration {
        switch base {
        case .standard:
            let configuration = MKStandardMapConfiguration(
                elevationStyle: .flat, emphasisStyle: isMuted ? .muted : .default)
            if excludesPointsOfInterest == true {
                configuration.pointOfInterestFilter = .excludingAll
            }
            return configuration
        case .imagery:
            return MKImageryMapConfiguration(elevationStyle: .flat)
        case .hybrid:
            let configuration = MKHybridMapConfiguration(elevationStyle: .flat)
            if excludesPointsOfInterest == true {
                configuration.pointOfInterestFilter = .excludingAll
            }
            return configuration
        }
    }
}

/// The one stored copy of "put a map behind my cards" — per rider, not per session, the same
/// scope and the same shape as `ShareCardPresetStore`.
///
/// **Absent means off**, and so does any value that was never written by this switch. The map
/// is the only part of the card that reaches the network, and a default that quietly did so
/// would be the wrong kind of surprise on a screen whose fine print says the image is handed
/// straight to the share sheet.
enum ShareCardMapStore {

    static let defaultsKey = "shareCardMap.v1"

    static func load(from defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func save(_ wanted: Bool, to defaults: UserDefaults) {
        defaults.set(wanted, forKey: defaultsKey)
    }
}
