import Foundation

/// **How much water a list row's tile is a picture of.**
///
/// A row draws its outline into a fixed tile, and the normalization puts the track in a
/// *square* inside that tile (`TrackThumbnail.Projection`, `TrackOutlineView.fit`): the
/// square is as wide as the tile's shorter side less the inset on both edges, and it is
/// centred. A map drawn behind the line has to be a picture of exactly that square, widened
/// to the tile's own shape — otherwise the two are drawn at two scales and the track sits
/// off in a corner of a map of somewhere slightly else (Jan, Beta 75).
///
/// Two numbers decide it and both are easy to get wrong by a few points: the **inset** is
/// every inset between the tile's edge and the square, not only the one the outline view
/// knows about, and the **span** is the square's side in metres. So the arithmetic lives
/// here, as a value a test can call, and the tile and the snapshotter read the same answer.
public enum TrackTileRegion {

    /// The metres a tile covers, per axis, around the centre of the track's own box.
    public struct Extent: Sendable, Equatable {
        /// East to west, in metres.
        public let widthM: Double
        /// North to south, in metres.
        public let heightM: Double
        /// What one point of the tile is worth on the water.
        public let metresPerPoint: Double

        public init(widthM: Double, heightM: Double, metresPerPoint: Double) {
            self.widthM = widthM
            self.heightM = heightM
            self.metresPerPoint = metresPerPoint
        }

        /// The tile's shape, which the region has to match or the snapshotter will widen
        /// one axis on its own and the two pictures part company.
        public var aspect: Double { heightM == 0 ? 0 : widthM / heightM }
    }

    /// The region for a tile of `width` × `height` points whose drawn square is inset by
    /// `inset` on every edge, over a track whose square is `spanM` metres a side.
    ///
    /// nil where the inset leaves no square to draw in — a tile too small to be a picture of
    /// anything, which is a layout mistake rather than a session without a map.
    public static func extent(spanM: Double, width: Double, height: Double,
                              inset: Double) -> Extent? {
        let square = min(width, height) - inset * 2
        guard square > 0, spanM > 0, width > 0, height > 0 else { return nil }
        let metresPerPoint = spanM / square
        return Extent(widthM: width * metresPerPoint, heightM: height * metresPerPoint,
                      metresPerPoint: metresPerPoint)
    }
}
