import Foundation
import HealthKit
import OSLog

/// The HealthKit half of a recording: the workout session that keeps the app alive, the live
/// builder that collects heart rate, and the saved workout that earns the rider his rings.
///
/// **`.surfingSports`, and the choice is not arbitrary.** HealthKit has no wingfoil type, no
/// windsurf type and no foiling type. The candidates were `.surfingSports`, `.sailing`,
/// `.paddleSports` and `.waterSports`; `.surfingSports` wins because it is board-riding
/// rather than boat-sailing, it is what Apple's own watchOS "Surfing" workout uses, and the
/// Health app renders it with the surf icon in the outdoor-water grouping. The real
/// discipline travels in the container's `meta.discipline` instead, where it can be exact.
///
/// It is also **the same choice `ios/WingFoil/App/HealthWriter.swift` already made** for
/// sessions the phone exports. The two had to agree: a rider whose Health timeline showed
/// "Surfing" for a Garmin session and something else for a watch session would reasonably
/// conclude the app could not make up its mind.
///
/// `@unchecked Sendable`: `HKHealthStore` and the session objects are touched only from the
/// main actor; the delegate callbacks hop out through `@Sendable` closures.
final class WorkoutBridge: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate,
                           @unchecked Sendable {

    private static let log = Logger(subsystem: "de.lahmann.wingfoil.watch", category: "workout")

    /// See the note above. Kept in one place so it cannot drift from `HealthWriter`.
    static let activityType: HKWorkoutActivityType = .surfingSports

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private let onHeartRate: @Sendable (Date, Double) -> Void
    private let onEndedUnexpectedly: @Sendable (String) -> Void

    init(onHeartRate: @escaping @Sendable (Date, Double) -> Void,
         onEndedUnexpectedly: @escaping @Sendable (String) -> Void) {
        self.onHeartRate = onHeartRate
        self.onEndedUnexpectedly = onEndedUnexpectedly
        super.init()
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Heart rate is *read* as well as written here, which is the one place this project
    /// reads from Health at all — the phone app never does. It is unavoidable: a live
    /// workout builder is the only way to get heart rate off the wrist, and it hands it back
    /// through the same store it writes to.
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let share: Set<HKSampleType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKObjectType.workoutType(),
        ]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
        } catch {
            Self.log.error("HealthKit authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    func start(at date: Date) throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType
        configuration.locationType = .outdoor

        let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store,
                                                     workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self

        self.session = session
        self.builder = builder

        // THE reason the app survives a wet, dark, pocketed wrist for two hours: an active
        // workout session is what watchOS keeps running. There is no `WKExtendedRuntimeSession`
        // here and there must not be — the two are alternatives, and the workout one is the
        // one that also produces a saved workout at the end.
        session.startActivity(with: date)
        builder.beginCollection(withStart: date) { ok, error in
            if !ok, let error {
                Self.log.error("beginCollection failed: \(error.localizedDescription)")
            }
        }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    /// Ends the session and saves the workout.
    ///
    /// **Failure here must never cost the rider the recording.** The container is assembled
    /// from files that are already on disk by the time this is called, so every step below
    /// is allowed to fail and be logged: the worst case is a session that reaches the phone
    /// with full analysis but earns no ring credit, which is a disappointment rather than a
    /// loss. The reverse ordering — saving to Health first and treating a failure as fatal —
    /// would throw away an afternoon to protect a badge.
    func end(at date: Date) async {
        guard let session, let builder else { return }
        session.end()
        do {
            try await builder.endCollection(at: date)
            let workout = try await builder.finishWorkout()
            Self.log.info("saved workout to HealthKit: \(workout?.uuid.uuidString ?? "none")")
        } catch {
            Self.log.error("could not save the workout to Health: \(error.localizedDescription)")
        }
        self.session = nil
        self.builder = nil
    }

    // MARK: - HKWorkoutSessionDelegate

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        Self.log.info("workout session \(fromState.rawValue) -> \(toState.rawValue)")
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: any Error) {
        Self.log.error("workout session failed: \(error.localizedDescription)")
        onEndedUnexpectedly(error.localizedDescription)
    }

    // MARK: - HKLiveWorkoutBuilderDelegate

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRateType),
              let statistics = workoutBuilder.statistics(for: heartRateType),
              let quantity = statistics.mostRecentQuantity() else { return }
        // The builder reports "there is new data", not the sample itself; the most recent
        // value at the moment of the callback is the reading. Its own timestamp is the
        // window end, which is what we want on a stream sampled every few seconds.
        let bpm = quantity.doubleValue(for: .count().unitDivided(by: .minute()))
        let at = statistics.mostRecentQuantityDateInterval()?.end ?? Date()
        onHeartRate(at, bpm)
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
