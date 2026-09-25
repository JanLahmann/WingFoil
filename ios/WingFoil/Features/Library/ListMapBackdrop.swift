import MapKit
import SwiftUI
import WingFoilKit

/// **The map under a library row's track** (item 6 of the 18 Sep 2026 round).
///
/// Off by default and switched on in Settings. A row's outline is normalized into a unit
/// square (`TrackThumbnail`), and the square carries the metres and the centroid it was
/// projected from, so the same square can be asked of MapKit as a picture of the water the
/// session was ridden on. The two then line up by construction rather than by eye.
///
/// **It never blocks a scroll.** A snapshot costs a network round trip, so it is built off
/// the main actor, once per session and map style, and written to the caches directory —
/// regenerable by definition, and the one place in this app where throwing the file away
/// costs nothing. A row draws the plain outline until the picture is there and never waits
/// for it.
enum ListMapBackdrop {

    /// The row's well, in points. The outline is inscribed as a square in it
    /// (`TrackOutlineView.fit`, `fillsBox` off), so the region has to be the wider box the
    /// square sits in or the picture and the line would be drawn at two scales.
    static let size = CGSize(width: 62, height: 44)

    /// **The one inset between the tile's edge and the drawn square**, which the row hands
    /// to `TrackOutlineView` and the region below is derived from.
    ///
    /// It was two numbers: the outline view's own 2 pt, and a `.padding(3)` the row wrapped
    /// it in. The region knew only the first, so the map was computed for a 40 pt square
    /// under a line drawn in a 34 pt one — an 18 % scale difference between the picture and
    /// the track on it, which reads as a track shoved off towards an edge rather than as a
    /// zoom (Jan, Beta 75). One constant, read by both halves, is the fix.
    static let inset: Double = 5

    /// The region that lands the unit square exactly where the outline draws it: the square
    /// the inset leaves, widened to the tile's own shape and centred on the track's box
    /// (`TrackTileRegion`, pinned by `TrackTileRegionTests`).
    static func region(for thumbnail: TrackThumbnail) -> MKCoordinateRegion? {
        guard let bounds = thumbnail.bounds,
              let centre = thumbnail.coordinate(x: 0.5, y: 0.5),
              let extent = TrackTileRegion.extent(spanM: bounds.spanM,
                                                  width: Double(size.width),
                                                  height: Double(size.height),
                                                  inset: inset) else { return nil }
        // `coordinate(x: 0.5, y: 0.5)` is the centre of the *normalized square*, which is
        // the centre of the track's own bounding box — the point the outline is centred on
        // in the tile. The region is centred there and is as many metres across as the tile
        // is points, so the two pictures are the same picture.
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centre.lat, longitude: centre.lon),
            latitudinalMeters: extent.heightM,
            longitudinalMeters: extent.widthM)
    }

    /// What the snapshotter is asked for, from the one choice every map in the app is drawn
    /// on (`MapStyleChoice.recipe`). The table is the kit's; this is the MapKit call it
    /// resolves to, exactly as the live maps resolve it.
    static func configuration(_ style: MapStyleChoice) -> MKMapConfiguration {
        let recipe = style.recipe
        switch recipe.base {
        case .standard:
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        case .hybrid:
            let configuration = MKHybridMapConfiguration(elevationStyle: .flat)
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        }
    }

    /// One snapshot, on whatever thread MapKit answers on. Nil for a track with no bounds,
    /// which is every thumbnail written before the geometry carried them.
    static func snapshot(for thumbnail: TrackThumbnail,
                         style: MapStyleChoice,
                         scale: CGFloat) async -> UIImage? {
        guard let region = region(for: thumbnail) else { return nil }
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        // **Always the dark ground** (Jan, build 99: "some maps are dark, others light; the
        // dark was better"). The trait collection used to carry the scale alone, so the
        // appearance was unspecified and the snapshotter resolved it against whatever the
        // calling thread's current traits happened to be — dark for one row, light for the
        // next, and the cache kept whichever came first. On the light map the teal track
        // is teal on pale blue water and disappears; on the dark one it reads. The tile is
        // a picture, not chrome, so it does not follow the phone's appearance.
        options.traitCollection = UITraitCollection { traits in
            traits.displayScale = scale
            traits.userInterfaceStyle = .dark
        }
        options.preferredConfiguration = configuration(style)
        return await withCheckedContinuation { continuation in
            MKMapSnapshotter(options: options).start(with: .global(qos: .utility)) { shot, _ in
                continuation.resume(returning: shot?.image)
            }
        }
    }

    // MARK: - The disk cache

    /// `Caches/listmaps/<session id>-<style>-dark.png`. Keyed by the style as well as the
    /// session, so switching to satellite does not show a row the grey picture it had. The
    /// `-dark` suffix retires every picture cached before the appearance was pinned, light
    /// or dark by accident; the old files are swept once (`sweepUnpinned`).
    static func fileURL(id: String, style: MapStyleChoice) -> URL {
        directory.appending(path: id + "-" + style.rawValue + "-dark.png")
    }

    static let directory: URL = {
        let url = URL.cachesDirectory.appending(path: "listmaps")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func read(id: String, style: MapStyleChoice) -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL(id: id, style: style)) else {
            return nil
        }
        return UIImage(data: data)
    }

    static func write(_ image: UIImage, id: String, style: MapStyleChoice) {
        guard let data = image.pngData() else { return }
        try? data.write(to: fileURL(id: id, style: style), options: .atomic)
    }

    /// The pictures from before the appearance was pinned: same directory, no `-dark`
    /// suffix. Nothing reads them any more, so they are only disk.
    static func sweepUnpinned() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !file.lastPathComponent.hasSuffix("-dark.png") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Everything, forgotten. "Start over" wipes the library these pictures are of.
    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
