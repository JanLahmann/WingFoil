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
public actor SpotNamer {

    public static let shared = SpotNamer()

    /// Apple throttles bursts; one request per second is comfortably under the limit.
    private let spacing: Duration = .milliseconds(1200)
    private var lastRequest: ContinuousClock.Instant?
    private var cache: [String: String] = [:]

    public init() {}

    /// Best available locality name, or nil when the lookup is unavailable.
    public func locality(lat: Double, lon: Double) async -> String? {
        let key = String(format: "%.3f,%.3f", lat, lon)
        if let hit = cache[key] { return hit }
        #if canImport(CoreLocation)
        if let last = lastRequest {
            let elapsed = ContinuousClock.now - last
            if elapsed < spacing { try? await Task.sleep(for: spacing - elapsed) }
        }
        lastRequest = ContinuousClock.now
        let location = CLLocation(latitude: lat, longitude: lon)
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
