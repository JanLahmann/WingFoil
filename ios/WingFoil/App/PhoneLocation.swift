// The one place the app asks Core Location anything, and it exists only for the watch
// map's "Where I am now" — a DEV door (docs/channels.md). The release and beta
// Info.plists have no NSLocation* string for the phone's own half, so this file must not
// be in those binaries.
#if DEV
import CoreLocation
import Foundation

/// Where the phone is standing, once, because the rider asked for a map of it.
///
/// WHY THE APP HAS THIS AT ALL. The phone has never tracked the rider — the watch does the
/// recording and this app reads the FIT it sends (ADR-019, and the usage string in
/// `project.yml` says so in as many words). The one thing it cannot answer without asking
/// Core Location is "draw the watch a map of *here*", which is the afternoon at a lake the
/// library has never seen. So: one fix, on a tap, never a running update, never in the
/// background. `CLLocationManager.requestLocation` is exactly that call — it delivers one
/// location and stops on its own — and nothing in this file starts `startUpdatingLocation`.
///
/// WHY IT NEVER ASKS BY ITSELF. `refreshWatchMapIfNeeded` runs at every launch and after
/// every import; a permission sheet on launch for a feature nobody opened would be the app
/// begging. The automatic pass therefore only calls in here when `isAuthorized` is already
/// true, which reads the stored status and prompts nobody.
///
/// THE CONCURRENCY TRAP. Core Location's delegate callbacks arrive on whatever thread the
/// framework feels like, carrying non-Sendable objects (`CLLocationManager`, `CLLocation`).
/// A `@MainActor` method used as a delegate callback crashes at runtime on Xcode 26 rather
/// than failing to compile, which is how the ConnectIQ link lost an afternoon. So every
/// callback below is `nonisolated`, pulls out the two or three Sendable values it needs —
/// a coordinate, a status — on whatever thread it was handed, and hops with
/// `Task { @MainActor in … }`. `ConnectIQCompanionLink` is the same pattern, deliberately.
@MainActor
final class PhoneLocation: NSObject, CLLocationManagerDelegate {

    /// How long a fix may take before the answer is "no". Long enough for a cold GPS start
    /// indoors, short enough that the Send button is not a spinner nobody can cancel.
    static let timeout: Duration = .seconds(10)

    private let manager = CLLocationManager()
    /// Everyone waiting on the one fix in flight. A list rather than a single continuation
    /// because the picker row and the send can both ask within a second of each other, and
    /// two `requestLocation` calls would be two prompts' worth of work for one answer.
    private var waiting: [CheckedContinuation<(lat: Double, lon: Double)?, Never>] = []
    private var isRequesting = false
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        // A spot's box is 3 km across and one cell is 25 m: a hundred-metre fix names the
        // right lake, and asking for better would spin the GPS for nothing.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Whether Core Location would answer without a prompt. Reading the status never asks
    /// the rider anything, which is the whole point: the quiet automatic pass consults this
    /// and stays quiet when it is false.
    var isAuthorized: Bool {
        let status = manager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    /// One fix, or `nil`.
    ///
    /// `nil` covers every way this can not work — never asked and then refused, refused
    /// long ago, restricted by a profile, Core Location erroring, or ten seconds of no sky
    /// — because from the map row's side they are one situation: there is no "here" to
    /// send, and the other map still goes.
    func current() async -> (lat: Double, lon: Double)? {
        let status = manager.authorizationStatus
        guard status != .denied, status != .restricted else { return nil }
        isRequesting = true
        if status == .notDetermined {
            // The prompt. The fix is asked for in the authorization callback, once there
            // is an answer to ask under.
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestLocation()
        }
        return await withCheckedContinuation { continuation in
            // No `await` between the request above and this line, so the main actor is
            // never re-entered in between: a callback cannot beat this append.
            waiting.append(continuation)
            armTimeout()
        }
    }

    // MARK: - Finishing, exactly once

    private func armTimeout() {
        guard timeoutTask == nil else { return }
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: PhoneLocation.timeout)
            guard !Task.isCancelled else { return }
            self?.finish(nil)
        }
    }

    private func finish(_ fix: (lat: Double, lon: Double)?) {
        guard isRequesting else { return }
        isRequesting = false
        timeoutTask?.cancel()
        timeoutTask = nil
        let pending = waiting
        waiting = []
        for continuation in pending { continuation.resume(returning: fix) }
    }

    /// The answer to the prompt, or the status Core Location announces once at startup.
    private func authorizationChanged(to status: CLAuthorizationStatus) {
        guard isRequesting else { return }
        switch status {
        case .notDetermined:
            // The sheet is still on screen. Nothing to do but wait — or time out.
            break
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            finish(nil)
        }
    }

    // MARK: - Delegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationChanged(to: status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else { return }
        let lat = coordinate.latitude, lon = coordinate.longitude
        Task { @MainActor in self.finish((lat: lat, lon: lon)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: any Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

#endif
