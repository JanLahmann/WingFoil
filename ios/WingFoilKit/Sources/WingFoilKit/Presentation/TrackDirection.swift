import Foundation

/// Which way the rider was going, as marks that can be drawn along the track.
///
/// A wingfoil track is loops: the same water crossed a dozen times, out and back. Drawn as
/// plain lines it says where he went and says nothing at all about which way round — and on
/// a session whose whole shape is "reach out, jibe, reach back", that is half the story
/// missing. Chevrons put the arrow of time back on the line.
///
/// The hard part is *how many*. A chevron every N samples is wrong at every zoom but one:
/// zoomed out it welds into a dotted line, zoomed in it disappears. So the spacing is set in
/// **screen points** and converted to metres through the map's current scale, which means
/// the answer changes with the camera and has to be recomputed when it moves.
///
/// All of it is pure geometry, kept here rather than in the map view because a decimation
/// that quietly returns 3 000 chevrons is a bug you feel as a stutter and cannot see in a
/// screenshot.
public enum TrackDirection {

    /// One positioned track sample, carrying the phase it was recorded in so a chevron can
    /// be tinted like the water under it.
    public struct Point: Sendable, Equatable {
        public var lat: Double
        public var lon: Double
        public var flying: Bool

        public init(lat: Double, lon: Double, flying: Bool) {
            self.lat = lat
            self.lon = lon
            self.flying = flying
        }
    }

    /// One direction mark: where it sits, which way it points, and which phase it belongs to.
    public struct Chevron: Identifiable, Sendable, Equatable {
        public var id: Int
        public var lat: Double
        public var lon: Double
        /// Course over ground at this point, degrees clockwise from true north.
        public var bearingDeg: Double
        public var flying: Bool
    }

    /// The camera's footprint, used to skip chevrons the rider cannot see. Zooming in makes
    /// this small, which is exactly why zooming in yields *more* marks on the visible stretch
    /// rather than the same handful spread over the whole session.
    public struct Box: Sendable, Equatable {
        public var minLat: Double
        public var maxLat: Double
        public var minLon: Double
        public var maxLon: Double

        public init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
            self.minLat = minLat
            self.maxLat = maxLat
            self.minLon = minLon
            self.maxLon = maxLon
        }

        /// Centred on a map region, grown by `pad` (a share of the span) so a chevron just
        /// off the edge still exists when the rider drags a little.
        public init(centerLat: Double, centerLon: Double,
                    latSpan: Double, lonSpan: Double, pad: Double = 0.15) {
            let dLat = latSpan * (0.5 + pad)
            let dLon = lonSpan * (0.5 + pad)
            self.init(minLat: centerLat - dLat, maxLat: centerLat + dLat,
                      minLon: centerLon - dLon, maxLon: centerLon + dLon)
        }

        public func contains(lat: Double, lon: Double) -> Bool {
            lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon
        }
    }

    /// Default gap between chevrons, in screen points — a little wider than a fingertip.
    /// Set by eye on the inline map: closer than this and a looping track collects arrows
    /// into what reads as a second dashed line, which buries the event dots it is supposed
    /// to sit behind. Sparse is the safe failure here — one arrow per leg still answers
    /// "which way round?", whereas a crowded line answers nothing.
    public static let defaultSpacingPoints: Double = 78
    /// Hard ceiling on marks per redraw. A cap rather than a truncation — see `chevrons`,
    /// which widens the spacing to fit instead of stopping half way along the track.
    public static let defaultMaxCount = 90

    // MARK: - Geometry

    /// Initial bearing from one coordinate to another, degrees clockwise from true north,
    /// normalized to 0..<360.
    ///
    /// The great-circle formula rather than a flat-earth `atan2(dLon, dLat)`: over a
    /// hundred metres the two agree, but the great-circle one is also correct across the
    /// antimeridian, and "correct everywhere" is cheaper to trust than "correct at Gardasee".
    public static func bearingDeg(fromLat: Double, fromLon: Double,
                                  toLat: Double, toLon: Double) -> Double {
        let phi1 = fromLat * .pi / 180
        let phi2 = toLat * .pi / 180
        let dLambda = (toLon - fromLon) * .pi / 180
        let y = sin(dLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLambda)
        guard y != 0 || x != 0 else { return 0 }
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Equirectangular metres — the same approximation the session detail uses to rank
    /// distances. Over a session-sized box the error is far below one chevron's spacing.
    public static func metresBetween(lat1: Double, lon1: Double,
                                     lat2: Double, lon2: Double) -> Double {
        let cosLat = cos((lat1 + lat2) / 2 * .pi / 180)
        let dx = (lon2 - lon1) * cosLat * 111_320
        let dy = (lat2 - lat1) * 110_540
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Ground metres per screen point for a map showing `latSpan × lonSpan` in a view of
    /// `size` points. MapKit fits the region, so the scale that governs is the *tighter*
    /// of the two axes — the one that had to shrink to make the region fit.
    public static func metresPerPoint(latSpan: Double, lonSpan: Double, centerLat: Double,
                                      widthPoints: Double, heightPoints: Double) -> Double {
        guard widthPoints > 0, heightPoints > 0 else { return 0 }
        let latMetres = latSpan * 110_540
        let lonMetres = lonSpan * 111_320 * cos(centerLat * .pi / 180)
        return max(latMetres / heightPoints, lonMetres / widthPoints)
    }

    // MARK: - Decimation

    /// Chevrons along `points`, one every `spacingPoints` screen points of travelled track.
    ///
    /// Two things keep this honest at both ends of the zoom range. Spacing is measured in
    /// **ground distance**, so a slow stretch and a fast one get the same visual rhythm
    /// rather than one arrow per sample where he was drifting. And `maxCount` is enforced by
    /// *widening* the spacing, never by stopping early: a track that is half arrowed and
    /// half bare reads as missing data.
    public static func chevrons(along points: [Point],
                                metresPerPoint: Double,
                                spacingPoints: Double = defaultSpacingPoints,
                                within box: Box? = nil,
                                maxCount: Int = defaultMaxCount) -> [Chevron] {
        guard points.count >= 2, metresPerPoint > 0, spacingPoints > 0, maxCount > 0 else {
            return []
        }

        // Cumulative ground distance along the polyline, plus how much of it is on screen.
        var cumulative = [Double](repeating: 0, count: points.count)
        var visibleM = 0.0
        for index in 1..<points.count {
            let step = metresBetween(lat1: points[index - 1].lat, lon1: points[index - 1].lon,
                                     lat2: points[index].lat, lon2: points[index].lon)
            cumulative[index] = cumulative[index - 1] + step
            if box.map({ $0.contains(lat: points[index].lat, lon: points[index].lon) }) ?? true {
                visibleM += step
            }
        }
        let totalM = cumulative[points.count - 1]
        guard totalM > 0 else { return [] }

        // The requested rhythm, widened just enough that what is on screen fits the budget.
        let spacingM = max(spacingPoints * metresPerPoint, visibleM / Double(maxCount))
        guard spacingM > 0 else { return [] }

        // Bearing is read over a short baseline around the anchor rather than between two
        // neighbouring samples: at 1 Hz a single step is a couple of metres of GPS noise and
        // would set the arrows spinning on a straight reach.
        let baseline = min(spacingM / 3, 30)

        var out: [Chevron] = []
        var distance = spacingM / 2          // half a gap in, so a short leg still gets one
        while distance < totalM, out.count < maxCount {
            defer { distance += spacingM }
            guard let anchor = interpolate(points, cumulative, at: distance) else { continue }
            guard box.map({ $0.contains(lat: anchor.lat, lon: anchor.lon) }) ?? true else {
                continue
            }
            let back = interpolate(points, cumulative, at: max(0, distance - baseline)) ?? anchor
            let ahead = interpolate(points, cumulative,
                                    at: min(totalM, distance + baseline)) ?? anchor
            let bearing = bearingDeg(fromLat: back.lat, fromLon: back.lon,
                                     toLat: ahead.lat, toLon: ahead.lon)
            out.append(Chevron(id: out.count, lat: anchor.lat, lon: anchor.lon,
                               bearingDeg: bearing, flying: anchor.flying))
        }
        return out
    }

    /// The position `distance` metres along the polyline. Phase comes from the sample the
    /// anchor sits *on* (not the one it is heading towards), so an arrow drawn a metre before
    /// a takeoff is still coloured off-foil, which is what the water under it was.
    private static func interpolate(_ points: [Point], _ cumulative: [Double],
                                    at distance: Double) -> Point? {
        guard let last = cumulative.last, last > 0 else { return nil }
        if distance <= 0 { return points.first }
        if distance >= last { return points.last }
        var lo = 0, hi = points.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= distance { lo = mid } else { hi = mid }
        }
        let step = cumulative[hi] - cumulative[lo]
        guard step > 0 else { return points[lo] }
        let fraction = (distance - cumulative[lo]) / step
        return Point(lat: points[lo].lat + (points[hi].lat - points[lo].lat) * fraction,
                     lon: points[lo].lon + (points[hi].lon - points[lo].lon) * fraction,
                     flying: points[lo].flying)
    }
}
