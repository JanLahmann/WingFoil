import CoreLocation
import CoreMotion
import Foundation
import OSLog

/// One position fix, reduced to values the moment it arrives.
///
/// The bridges below hand these across the concurrency boundary rather than handing over
/// `CLLocation` and `CMAccelerometerData` objects: a plain `Sendable` struct is provably safe
/// to move between isolation domains, and the conversion has to happen somewhere anyway.
/// It is also where CoreLocation's "no reading" convention is normalised away — the framework
/// signals an unusable channel with a **negative** number, and a -1 m/s that escaped into the
/// recording would be a real number to the analysis engine and a nonsense one to the rider.
struct Fix: Sendable {
    var timestamp: Date
    var lat: Double
    var lon: Double
    var speedMps: Double?
    var horizontalAccuracyM: Double?
    var altitudeM: Double?

    init(_ location: CLLocation) {
        timestamp = location.timestamp
        lat = location.coordinate.latitude
        lon = location.coordinate.longitude
        speedMps = location.speed >= 0 ? location.speed : nil
        horizontalAccuracyM = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
        altitudeM = location.verticalAccuracy >= 0 ? location.altitude : nil
    }
}

/// CoreLocation, reduced to a stream of `Fix`.
///
/// `@unchecked Sendable` because it owns a `CLLocationManager`, which is not: every method
/// here is called from the main actor and the delegate callbacks arrive on the queue the
/// manager was created on, which is the same one. The callbacks it hands out are `@Sendable`
/// and do their own hop.
final class LocationBridge: NSObject, CLLocationManagerDelegate, @unchecked Sendable {

    private static let log = Logger(subsystem: "de.lahmann.wingfoil.watch", category: "location")

    private let manager = CLLocationManager()
    private let onFix: @Sendable (Fix) -> Void
    private let onAuthorization: @Sendable (CLAuthorizationStatus) -> Void

    init(onFix: @escaping @Sendable (Fix) -> Void,
         onAuthorization: @escaping @Sendable (CLAuthorizationStatus) -> Void) {
        self.onFix = onFix
        self.onAuthorization = onAuthorization
        super.init()
        manager.delegate = self
        // Wingfoiling is a 25-knot sport where the speed *is* the measurement, so this asks
        // for the best fix the watch can give and takes the battery cost — a session is two
        // hours, not a day. `distanceFilter` off because a rider sitting on the board
        // waiting for a gust is still part of the session.
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Fixes start arriving before the rider presses start, so the start screen can say
    /// whether the watch actually knows where it is.
    func startUpdating(background: Bool) {
        // Only legal once the workout session exists, and only with the `location`
        // background mode in the Info.plist — without both, watchOS throws.
        manager.allowsBackgroundLocationUpdates = background
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.allowsBackgroundLocationUpdates = false
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        for location in locations { onFix(Fix(location)) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorization(manager.authorizationStatus)
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: any Error) {
        // Not fatal and deliberately not surfaced: CoreLocation reports a transient
        // `kCLErrorLocationUnknown` whenever the sky is briefly gone, which on the water is
        // every time a wave goes over the wrist.
        Self.log.debug("location error: \(error.localizedDescription)")
    }
}

/// The wrist accelerometer at a fixed rate, delivered as `(t, |a|)` pairs.
///
/// **Magnitude only, gravity included** — a resting wrist reads about 1.0 g. That is the same
/// signal the Garmin app records (`AccelSample`), and it is what `PumpAnalyzer` expects: the
/// pump detector band-passes 0.5–2.5 Hz, which removes the gravity component as a matter of
/// arithmetic, and it is orientation-free by construction because a wingfoiler's wrist
/// rotates constantly (docs/algorithms.md "Pumping").
///
/// **50 Hz.** `PumpConfig.resampleHz` is 25, so this is exactly 2× the grid the analysis runs
/// on: fast enough that the box-average has two samples a bin, slow enough that a two-hour
/// session is 2.9 MB rather than 5.8. Sampling *at* 25 Hz would put the band's upper edge
/// uncomfortably close to Nyquist.
final class MotionSampler: @unchecked Sendable {

    private static let log = Logger(subsystem: "de.lahmann.wingfoil.watch", category: "motion")

    static let rateHz: Double = 50

    private let motion = CMMotionManager()
    /// Its own serial queue: the handler fires 50 times a second and must never be behind the
    /// UI in the main queue.
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "de.lahmann.wingfoil.watch.motion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()

    var isAvailable: Bool { motion.isAccelerometerAvailable }

    /// `onSample` receives `(uptime, magnitudeG)` — the raw device-uptime clock, which the
    /// recorder rebases onto session time. Called on the sampler's own queue, never on main.
    func start(onSample: @escaping @Sendable (Double, Double) -> Void) {
        guard motion.isAccelerometerAvailable else {
            Self.log.error("no accelerometer on this device — the session will have no pump data")
            return
        }
        motion.accelerometerUpdateInterval = 1 / Self.rateHz
        motion.startAccelerometerUpdates(to: queue) { data, error in
            guard let data else {
                if let error { Self.log.error("accelerometer stopped: \(error.localizedDescription)") }
                return
            }
            let a = data.acceleration
            onSample(data.timestamp, (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot())
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
    }
}
