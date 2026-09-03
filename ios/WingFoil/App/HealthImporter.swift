import CoreLocation
import Foundation
import HealthKit
import WingFoilKit

/// The Apple workout types a rider may record a wingfoil session under.
///
/// HealthKit has no wingfoil, windsurf or foiling activity, so Apple's Workout app offers
/// these three and the rider picks one — which is why the type says nothing about the
/// discipline and CleanJibe does not try to read one out of it (`HealthImport.discipline`).
/// The list is short on purpose: every type added here is another way for a run, a swim or a
/// paddle to be offered as a wingfoil session.
///
/// Surfing and Water Sports are on by default because they are what Apple's own Workout app
/// puts in front of a wingfoiler, and `.surfingSports` is also what CleanJibe writes
/// (`HealthWriter`) and what the watch app records under. Sailing is off by default: a rider
/// who uses it means it, and everybody else has a boat in that bucket.
enum HealthWorkoutType: String, CaseIterable, Identifiable, Sendable {
    case surfingSports
    case waterSports
    case sailing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .surfingSports: "Surfing"
        case .waterSports: "Water Sports"
        case .sailing: "Sailing"
        }
    }

    var activityType: HKWorkoutActivityType {
        switch self {
        case .surfingSports: .surfingSports
        case .waterSports: .waterSports
        case .sailing: .sailing
        }
    }

    static let defaults: Set<HealthWorkoutType> = [.surfingSports, .waterSports]

    /// The Health type of a workout we are looking at, or nil for anything we never asked for.
    static func named(_ type: HKWorkoutActivityType) -> HealthWorkoutType? {
        allCases.first { $0.activityType == type }
    }
}

/// One workout Health is offering, as much as can be known before its route is fetched.
///
/// Deliberately not an `HKWorkout`: the list view, the store and the tests all handle these,
/// and none of them should need HealthKit in scope to do it.
struct HealthWorkoutCandidate: Identifiable, Sendable, Equatable {
    /// `HKWorkout.uuid` — stable for the life of the workout in Health, which is what makes
    /// "already imported" answerable exactly rather than by inference.
    let id: UUID
    let start: Date
    let durationS: TimeInterval
    let type: HealthWorkoutType
    /// The app that recorded it, as Health names it ("Workout", "Fitness", …).
    let sourceName: String
    /// True when this workout is already in the library. Two independent answers, ORed:
    /// its uuid is in the imported set (exact), or a session already sits on its dedupe key
    /// (which catches the same afternoon arriving from intervals.icu first).
    var isAlreadyImported = false

    var end: Date { start.addingTimeInterval(durationS) }
}

/// Reads workouts recorded with **Apple's own Workout app** out of Health
/// (docs/decisions.md ADR-017).
///
/// The peer of `HealthWriter`, which is write-only and says why in its own header. That
/// reasoning has not changed and is not contradicted here: HealthKit still hands out no route
/// for a *Garmin*-synced workout (ADR-003), so Health remains useless as a way to get at the
/// recordings this app was built around. What it does have is the one recording an Apple Watch
/// makes for itself — an `HKWorkoutRoute` of `CLLocation`s with Doppler speed, and the heart
/// rate beside it — and that is a real source, for the rider who owns no Garmin at all.
///
/// **Everything here is a read.** This type never writes to Health, never deletes, and never
/// modifies a workout. The one thing it does write is a set of workout uuids in `UserDefaults`,
/// on this phone, so the same afternoon is not offered twice.
///
/// **Our own workouts are skipped.** Both the CleanJibe watch app and `HealthWriter` file
/// `.surfingSports` workouts, and those sessions are in the library already — by a better route
/// in both cases. Offering them back would be the app importing its own exports.
actor HealthImporter {

    static let shared = HealthImporter()

    private let store = HKHealthStore()

    /// Bundle-id prefix of everything we ship. The watch app is
    /// `de.lahmann.wingfoil.watchkitapp` and the phone is `de.lahmann.wingfoil`, so one
    /// prefix covers both — and covers a future extension nobody remembers to add here.
    static let ourBundlePrefix = "de.lahmann.wingfoil"

    nonisolated var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var workoutType: HKObjectType { HKObjectType.workoutType() }
    private var routeType: HKObjectType { HKSeriesType.workoutRoute() }
    private var heartType: HKObjectType { HKQuantityType(.heartRate) }

    // MARK: - Permission

    /// Asks for read access to workouts, their routes and heart rate.
    ///
    /// **A read denial is invisible by design.** HealthKit never reveals whether the rider
    /// said no to a read — that is deliberate on Apple's part, because the answer itself would
    /// leak whether the data exists — so this returns whether the *prompt* completed, not
    /// whether it was granted. The honest report to the rider is therefore made of what comes
    /// back: an empty list, with a line saying where to change his mind
    /// (Settings → Health → Data Access & Devices → CleanJibe).
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [],
                                                 read: [workoutType, routeType, heartType])
            return true
        } catch {
            return false
        }
    }

    // MARK: - Listing

    /// Every workout of the chosen types, newest first, with ours filtered out.
    ///
    /// `oldest` bounds the query the way the intervals.icu sync bounds its own: a rider with
    /// ten years of Health history is not asking to be shown a decade of it, and an unbounded
    /// query is also the one that is slow.
    func candidates(types: Set<HealthWorkoutType>, oldest: Date,
                    imported: Set<UUID>) async -> [HealthWorkoutCandidate] {
        guard HKHealthStore.isHealthDataAvailable(), !types.isEmpty else { return [] }
        let byType = types.map { HKQuery.predicateForWorkouts(with: $0.activityType) }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSCompoundPredicate(orPredicateWithSubpredicates: byType),
            HKQuery.predicateForSamples(withStart: oldest, end: nil),
        ])
        let workouts = await self.workouts(matching: predicate)
        return workouts.compactMap { workout in
            guard !Self.isOurs(workout), let type = HealthWorkoutType.named(workout.workoutActivityType)
            else { return nil }
            return HealthWorkoutCandidate(
                id: workout.uuid,
                start: workout.startDate,
                durationS: workout.duration,
                type: type,
                sourceName: workout.sourceRevision.source.name,
                isAlreadyImported: imported.contains(workout.uuid))
        }
    }

    /// A workout CleanJibe itself put in Health — our watch app's live save, or
    /// `HealthWriter`'s after-the-fact stub. Both are already in the library, by a better road.
    static func isOurs(_ workout: HKWorkout) -> Bool {
        workout.sourceRevision.source.bundleIdentifier.hasPrefix(ourBundlePrefix)
    }

    /// `HKMetadataKeyExternalUUID` when the workout carries one. Ours carry a session id
    /// there; a caller can use it as a second, bundle-id-independent way to recognise a
    /// session the library already holds.
    static func externalUUID(_ workout: HKWorkout) -> String? {
        workout.metadata?[HKMetadataKeyExternalUUID] as? String
    }

    // MARK: - One workout, mapped

    /// Fetches a workout's route and heart rate and maps it to the bytes the ordinary import
    /// path takes (`HealthImport.container`).
    ///
    /// Throws `HealthImport.ImportError.noRoute` for a workout Health kept no positions for —
    /// an indoor session, a watch that never got a fix, or a rider who denied location. That
    /// is a *reason*, not a crash: the import screen counts it as skipped and says so.
    func container(for id: UUID, appVersion: String) async throws -> (data: Data,
                                                                     name: String,
                                                                     start: Date) {
        guard let workout = await workout(id: id) else { throw HealthImport.ImportError.noRoute }
        let locations = await self.locations(for: workout)
        let heart = await self.heartRate(for: workout)
        let offset = Self.utcOffsetS(of: workout)

        let route = locations.map {
            HealthRouteSample(timestamp: $0.timestamp,
                              lat: $0.coordinate.latitude,
                              lon: $0.coordinate.longitude,
                              altitudeM: $0.verticalAccuracy >= 0 ? $0.altitude : nil,
                              horizontalAccuracyM: $0.horizontalAccuracy,
                              speedMps: $0.speed,
                              courseDeg: $0.course)
        }
        let data = try HealthImport.container(
            sessionId: workout.uuid.uuidString,
            activityType: HealthWorkoutType.named(workout.workoutActivityType)?.rawValue
                ?? "workout",
            route: route,
            heart: heart,
            utcOffsetS: offset,
            producer: "CleanJibe iOS \(appVersion) (Apple Health)")
        let start = route.first?.timestamp ?? workout.startDate
        return (data, HealthImport.filename(start: start, utcOffsetS: offset), start)
    }

    /// The workout's own clock, when it wrote one down.
    ///
    /// `HKMetadataKeyTimeZone` is an IANA name and an *exact* answer — resolved at the
    /// session's own instant, so DST is included. Apple's Workout app usually writes none, and
    /// nil is then passed through honestly rather than replaced with this phone's current zone:
    /// see `WatchSessionMeta.utcOffsetKnown`.
    static func utcOffsetS(of workout: HKWorkout) -> Int? {
        guard let name = workout.metadata?[HKMetadataKeyTimeZone] as? String,
              let zone = TimeZone(identifier: name) else { return nil }
        return zone.secondsFromGMT(for: workout.startDate)
    }

    // MARK: - Watching for new ones

    /// Asks HealthKit to wake the app when a workout is added, and to keep doing so in the
    /// background where iOS allows it.
    ///
    /// **Background delivery is best-effort and this call may simply fail.** It needs the
    /// HealthKit *background delivery* entitlement, which the manual "WingFoil App Store"
    /// provisioning profile does not carry today — the same situation ADR-011 documents for the
    /// widget's app group, and handled the same way: ask, accept a refusal, and never depend on
    /// it. Even when it is granted, iOS decides when a background app runs and may hold a
    /// delivery for hours. The launch-and-foreground check is the path that always works;
    /// this only shortens the wait.
    ///
    /// Returns the observer query so the caller can stop it, or nil when Health is unavailable.
    @discardableResult
    func observeNewWorkouts(_ onChange: @escaping @Sendable () -> Void) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let query = HKObserverQuery(sampleType: HKObjectType.workoutType(),
                                    predicate: nil) { _, completion, _ in
            onChange()
            // The handler MUST be called, error or not: HealthKit escalates an unacknowledged
            // background delivery and eventually stops sending them altogether.
            completion()
        }
        store.execute(query)
        // `.hourly` rather than `.immediate`: a workout that finished five minutes ago is not
        // urgent, and the rate limit is what keeps this from being a battery story.
        try? await store.enableBackgroundDelivery(for: HKObjectType.workoutType(),
                                                  frequency: .hourly)
        return true
    }

    // MARK: - HealthKit plumbing

    /// Every workout matching a predicate, newest first.
    private func workouts(matching predicate: NSPredicate) async -> [HKWorkout] {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
    }

    private func workout(id: UUID) async -> HKWorkout? {
        await workouts(matching: HKQuery.predicateForObject(with: id)).first
    }

    /// The workout's route, flattened into one time-sorted run of `CLLocation`s.
    ///
    /// Two queries deep, because that is how HealthKit models it: a workout owns zero or more
    /// `HKWorkoutRoute` series objects, and each series is *streamed* rather than returned.
    /// A workout with no route comes back empty, which `HealthImport` turns into a named
    /// reason rather than an empty session.
    private func locations(for workout: HKWorkout) async -> [CLLocation] {
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: HKSeriesType.workoutRoute(),
                                              predicate: HKQuery.predicateForObjects(from: workout),
                                              anchor: nil,
                                              limit: HKObjectQueryNoLimit) { _, samples, _, _, _ in
                continuation.resume(returning: samples as? [HKWorkoutRoute] ?? [])
            }
            store.execute(query)
        }
        var all: [CLLocation] = []
        for route in routes { all.append(contentsOf: await self.locations(in: route)) }
        return all.sorted { $0.timestamp < $1.timestamp }
    }

    /// One route series, drained. `HKWorkoutRouteQuery`'s handler fires repeatedly with
    /// batches and once more with `done` — so the continuation is guarded, because resuming a
    /// checked continuation twice is a crash rather than a warning.
    private func locations(in route: HKWorkoutRoute) async -> [CLLocation] {
        await withCheckedContinuation { continuation in
            let box = ContinuationBox(continuation)
            var collected: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { query, batch, done, error in
                if let batch { collected.append(contentsOf: batch) }
                guard done || error != nil else { return }
                if error != nil { self.store.stop(query) }
                box.finish(collected)
            }
            store.execute(query)
        }
    }

    /// Resumes a checked continuation exactly once, whatever HealthKit does with the handler.
    private final class ContinuationBox: @unchecked Sendable {
        private var continuation: CheckedContinuation<[CLLocation], Never>?
        private let lock = NSLock()

        init(_ continuation: CheckedContinuation<[CLLocation], Never>) {
            self.continuation = continuation
        }

        func finish(_ value: [CLLocation]) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }

    /// The workout's heart-rate samples, on their own clock — `WatchSessionParser` joins them
    /// onto the record timeline with the same ±5 s rule every other source is held to.
    private func heartRate(for workout: HKWorkout) async -> [HealthHeartSample] {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: HKQuantityType(.heartRate),
                                      predicate: HKQuery.predicateForObjects(from: workout),
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [sort]) { _, samples, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                let beats = (samples as? [HKQuantitySample] ?? []).map {
                    HealthHeartSample(timestamp: $0.startDate,
                                      bpm: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: beats)
            }
            store.execute(query)
        }
    }
}
