import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

/// Reverse-geocodes a spot centroid to a human name ("Nago-Torbole").
///
/// Deliberately best-effort: Apple's geocoder is network-only and rate-limited to a
/// handful of requests per minute, so every failure — offline, throttled, no placemark —
/// simply leaves the spot on its `Spot N` placeholder, which the rider can rename. The
/// serial actor plus the delay keep us inside the rate limit for a first-launch backfill
/// of a handful of spots.
///
/// **This is the app's one outbound use of a coordinate**, and the privacy page and the App
/// Store description both name it (docs/presentation.md, "What leaves the phone"). What goes
/// is a *rounded* spot centroid — `roundedForLookup`, three decimal places, about 110 m —
/// and nothing else: no session, no track, no identifier, no account, one request per spot
/// and only for a spot that has no name yet. Rounding is applied to the coordinate that is
/// actually sent, not merely to the cache key, so the sentence those two pages print is the
/// sentence the code obeys.
public actor SpotNamer {

    public static let shared = SpotNamer()

    /// Apple throttles bursts; one request per second is comfortably under the limit.
    private let spacing: Duration = .milliseconds(1200)
    private var lastRequest: ContinuousClock.Instant?
    private var cache: [String: String] = [:]

    /// Decimal places the coordinate is rounded to before it leaves the phone. Three is
    /// ~110 m of latitude — finer than the 500 m clustering radius, so the answer is the
    /// same town, and coarser than the centroid of the afternoons that made the spot.
    public static let lookupPrecision = 3

    /// The coordinate as it is sent: rounded, and the cache key built from the same pair.
    public static func roundedForLookup(lat: Double, lon: Double) -> (lat: Double, lon: Double) {
        let scale = pow(10.0, Double(lookupPrecision))
        return ((lat * scale).rounded() / scale, (lon * scale).rounded() / scale)
    }

    public init() {}

    /// Best available locality name, or nil when the lookup is unavailable.
    public func locality(lat: Double, lon: Double) async -> String? {
        let fix = Self.roundedForLookup(lat: lat, lon: lon)
        let key = String(format: "%.3f,%.3f", fix.lat, fix.lon)
        if let hit = cache[key] { return hit }
        #if canImport(CoreLocation)
        if let last = lastRequest {
            let elapsed = ContinuousClock.now - last
            if elapsed < spacing { try? await Task.sleep(for: spacing - elapsed) }
        }
        lastRequest = ContinuousClock.now
        let location = CLLocation(latitude: fix.lat, longitude: fix.lon)
        guard let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location),
              let placemark = placemarks.first else { return nil }
        let name = placemark.locality
            ?? placemark.subAdministrativeArea
            ?? placemark.name
            ?? placemark.administrativeArea
        if let name { cache[key] = name }
        return name
        #else
        return nil
        #endif
    }

    /// The closure shape `LibraryStore.nameAutoSpots` expects.
    public nonisolated var resolver: @Sendable (Double, Double) async -> String? {
        { [self] lat, lon in await locality(lat: lat, lon: lon) }
    }
}
