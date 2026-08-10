import Foundation
import HealthKit
import WingFoilKit

/// Optional, opt-in, **write-only** Apple Health export (plan phase 4).
///
/// *Why write-only:* HealthKit never hands out `HKWorkoutRoute` for Garmin-synced
/// workouts (plan §2), so it is useless as a source; the only thing it adds is that a
/// wingfoil session shows up in the Health app's activity history next to everything else.
///
/// *Workout type:* HealthKit has no wingfoil, windsurf or foiling activity type. The
/// options are `.surfingSports`, `.sailing`, `.paddleSports` and the catch-all
/// `.waterSports`. We write **`.surfingSports`** — it is the type Apple's own watchOS
/// "Surfing" workout uses, it is board-riding rather than boat-sailing, and the Health
/// app renders it with the surf icon and the right "outdoor water" grouping. The
/// discipline the session really was travels in the metadata, so nothing is lost.
actor HealthWriter {

    static let shared = HealthWriter()

    private let store = HKHealthStore()

    nonisolated var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks for permission to *add* workouts. HealthKit deliberately never reveals a
    /// read denial, but a share denial is visible, so a "no" can be reported honestly.
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let workout = HKObjectType.workoutType()
        do {
            try await store.requestAuthorization(toShare: [workout], read: [])
        } catch {
            return false
        }
        return store.authorizationStatus(for: workout) == .sharingAuthorized
    }

    /// Adds one session as a workout. Returns false when Health is unavailable, not
    /// authorized, or the write failed — the caller then simply keeps the session in its
    /// "not exported yet" set and tries again later.
    func write(_ row: SessionRow) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(),
              store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized,
              row.durationS > 0 else { return false }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .surfingSports
        configuration.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration,
                                       device: .local())
        let end = row.startDate.addingTimeInterval(row.durationS)
        do {
            try await builder.beginCollection(at: row.startDate)
            try await builder.addMetadata(metadata(for: row))
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            return true
        } catch {
            return false
        }
    }

    /// HealthKit accepts String/NSNumber/Date/HKQuantity values under custom keys. The
    /// external UUID is our session id, so a re-export would replace rather than duplicate.
    private func metadata(for row: SessionRow) -> [String: Any] {
        var metadata: [String: Any] = [
            HKMetadataKeyExternalUUID: row.id,
            HKMetadataKeyWasUserEntered: false,
            "WingFoilDiscipline": row.discipline ?? row.sport ?? "wingfoil",
            "WingFoilSourceClass": row.sourceClass,
        ]
        if let distanceKm = row.distanceKm {
            metadata[HKMetadataKeyGroupFitness] = false
            metadata["WingFoilDistanceKm"] = NSNumber(value: distanceKm)
        }
        if let foilPct = row.foilPct { metadata["WingFoilFoilPercent"] = NSNumber(value: foilPct) }
        if let flights = row.flightCount { metadata["WingFoilFlights"] = NSNumber(value: flights) }
        if let best = row.best2sKn { metadata["WingFoilBest2sKn"] = NSNumber(value: best) }
        return metadata
    }
}
