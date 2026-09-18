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

    /// What `TrackOutlineView` insets its fit by, on each edge.
    static let padding: Double = 2

    /// The region that lands the unit square exactly where the outline draws it.
    static func region(for thumbnail: TrackThumbnail) -> MKCoordinateRegion? {
        guard let bounds = thumbnail.bounds,
              let centre = thumbnail.coordinate(x: 0.5, y: 0.5) else { return nil }
        // The square the unit box is drawn into: the shorter side of the well, less the
        // inset on both edges. Metres per point follows from it.
        let square = min(size.width, size.height) - padding * 2
        guard square > 0 else { return nil }
        let metresPerPoint = bounds.spanM / Double(square)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centre.lat, longitude: centre.lon),
            latitudinalMeters: Double(size.height) * metresPerPoint,
            longitudinalMeters: Double(size.width) * metresPerPoint)
    }

    /// What the snapshotter is asked for, from the one choice every map in the app is drawn
    /// on (`MapStyleChoice.recipe`). The table is the kit's; this is the MapKit call it
    /// resolves to, exactly as the live maps resolve it.
    static func configuration(_ style: MapStyleChoice) -> MKMapConfiguration {
        let recipe = style.recipe
        switch recipe.base {
        case .standard:
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.emphasisStyle = recipe.isMuted ? .muted : .default
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        case .imagery:
            return MKImageryMapConfiguration(elevationStyle: .flat)
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
        options.traitCollection = UITraitCollection(displayScale: scale)
        options.preferredConfiguration = configuration(style)
        return await withCheckedContinuation { continuation in
            MKMapSnapshotter(options: options).start(with: .global(qos: .utility)) { shot, _ in
                continuation.resume(returning: shot?.image)
            }
        }
    }

    // MARK: - The disk cache

    /// `Caches/listmaps/<session id>-<style>.png`. Keyed by the style as well as the
    /// session, so switching to satellite does not show a row the grey picture it had.
    static func fileURL(id: String, style: MapStyleChoice) -> URL {
        directory.appending(path: id + "-" + style.rawValue + ".png")
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

    /// Everything, forgotten. "Start over" wipes the library these pictures are of.
    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
