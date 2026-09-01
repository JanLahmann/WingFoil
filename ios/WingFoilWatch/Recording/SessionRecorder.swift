import CoreLocation
import Foundation
import OSLog
import WatchKit

/// Where a recording lives on the watch, in two stages.
///
/// `Recordings/<id>/` holds the three raw streams *while* the session runs — appended to as
/// the sensors fire, so nothing large is ever only in memory. `Outbox/<id>.cjw` holds the
/// assembled container *after* it stops, until WatchConnectivity says the phone has it.
///
/// The two-stage split is what makes a crash survivable. `meta.json` is written into the
/// recording directory at **start**, not at stop, so a session that was interrupted by a
/// jetsam, a flat battery or a genuine bug still has everything needed to be assembled and
/// sent on the next launch (`SessionRecorder.recoverInterruptedSessions`). watchOS will kill
/// an app it wants the memory back from; the rider should not have to know that.
enum SessionPaths {

    static func root() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return base
    }

    static func recordings() throws -> URL {
        let url = try root().appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func outbox() throws -> URL {
        let url = try root().appendingPathComponent("Outbox", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// An on/off flag the 50 Hz accelerometer handler can read without touching the main actor.
///
/// The handler runs on its own queue fifty times a second. Asking it to hop to the main actor
/// to find out whether the session is paused would put fifty scheduler round-trips a second
/// in the path of eight bytes, and would make the sensor's timing depend on how busy the UI
/// is. So the one bit it needs travels in a lock instead.
final class RecordingGate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false

    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return open
    }

    func set(_ value: Bool) {
        lock.lock()
        open = value
        lock.unlock()
    }
}

/// One finished session, as the summary screen shows it.
struct RecordedSummary: Equatable, Sendable {
    var durationS: Double
    var distanceM: Double
    var maxSpeedMps: Double
    var trackCount: Int
    var heartCount: Int
    var accelCount: Int
    var queuedForTransfer: Bool
}

/// The recorder: everything between the rider pressing START and a `.cjw` container being
/// handed to WatchConnectivity.
///
/// **This app records; it does not analyse.** There is no flight detection, no turn
/// detection, no pump counting and no record window on the wrist — those are the phone's job
/// (`WingFoilKit/AnalysisEngine`), and doing them twice would mean two implementations that
/// could disagree about the same afternoon. The watch's contract is narrower and stricter:
/// capture the four channels honestly, on one clock, and lose nothing.
@MainActor
@Observable
final class SessionRecorder {

    private static let log = Logger(subsystem: "de.lahmann.wingfoil.watch", category: "recorder")

    enum Phase: Equatable {
        case idle
        case starting
        case recording
        case paused
        case saving
        case finished
        case failed(String)
    }

    // MARK: Published state

    private(set) var phase: Phase = .idle
    /// Horizontal accuracy of the most recent fix, in metres — the start screen's GPS status.
    private(set) var fixAccuracyM: Double?
    private(set) var lastFixAt: Date?
    private(set) var locationAuthorization: CLAuthorizationStatus = .notDetermined
    private(set) var healthAuthorized = false

    private(set) var speedMps: Double = 0
    private(set) var maxSpeedMps: Double = 0
    private(set) var distanceM: Double = 0
    private(set) var heartRateBpm: Double?
    private(set) var elapsedS: Double = 0
    private(set) var summary: RecordedSummary?

    /// A fix within the last ten seconds, accurate to better than 50 m. What the start screen
    /// means by "ready" — not "CoreLocation returned something once".
    var hasUsableFix: Bool {
        guard let lastFixAt, let fixAccuracyM else { return false }
        return Date().timeIntervalSince(lastFixAt) < 10 && fixAccuracyM <= 50
    }

    // MARK: Collaborators

    private var location: LocationBridge?
    private let motion = MotionSampler()
    private var workout: WorkoutBridge?

    // MARK: Recording state

    private var sessionId = ""
    private var startDate = Date()
    /// The device's monotonic clock at start. The accelerometer timestamps are on this clock,
    /// so rebasing them here keeps the pump stream immune to a wall-clock adjustment mid
    /// session. The track and heart streams are on the wall clock, anchored at the same
    /// instant; the two agree at t = 0 and can only drift by whatever NTP steps the watch
    /// during a session, which is milliseconds.
    private var startUptime: Double = 0
    private var directory: URL?
    private var trackWriter: StreamFileWriter?
    private var heartWriter: StreamFileWriter?
    private var accelWriter: StreamFileWriter?
    /// Set when a pause ends, so the next fix is marked as a declared break — the same claim
    /// a GPX `<trkseg>` boundary makes, and the phone's `TrackCleaner` reads it the same way.
    private var pendingGap = false
    private var lastFixLatLon: (lat: Double, lon: Double)?
    private var ticker: Task<Void, Never>?
    /// Closed while paused and after stop, so the accelerometer handler can decide for itself
    /// whether to write without ever asking the main actor.
    private let accelGate = RecordingGate()

    // MARK: - Lifecycle

    func prepare() {
        if location == nil {
            location = LocationBridge(
                onFix: { [weak self] fix in
                    Task { @MainActor in self?.handle(fix) }
                },
                onAuthorization: { [weak self] status in
                    Task { @MainActor in self?.handle(authorization: status) }
                })
        }
        locationAuthorization = location?.authorizationStatus ?? .notDetermined
        if locationAuthorization == .notDetermined { location?.requestAuthorization() }
        // Fixes before START, so the rider can see whether the watch knows where it is
        // rather than finding out thirty seconds into the first run.
        location?.startUpdating(background: false)

        Task { await requestHealthAuthorization() }
        SessionTransfer.shared.activate()
        // Order matters: recovery only *assembles* interrupted sessions into the outbox, and
        // the single sweep below is what queues them. Doing both jobs in both places would
        // hand the same file to WatchConnectivity twice on every launch.
        recoverInterruptedSessions()
        sweepOutbox()
    }

    private func requestHealthAuthorization() async {
        let bridge = makeWorkoutBridge()
        healthAuthorized = await bridge.requestAuthorization()
    }

    private func makeWorkoutBridge() -> WorkoutBridge {
        if let workout { return workout }
        let bridge = WorkoutBridge(
            onHeartRate: { [weak self] at, bpm in
                Task { @MainActor in self?.handle(heartRateAt: at, bpm: bpm) }
            },
            onEndedUnexpectedly: { [weak self] message in
                Task { @MainActor in self?.workoutFailed(message) }
            })
        workout = bridge
        return bridge
    }

    // MARK: - Start

    func start() {
        guard phase == .idle || phase == .finished else { return }
        phase = .starting
        summary = nil

        let id = UUID().uuidString
        let now = Date()
        do {
            let dir = try SessionPaths.recordings().appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            trackWriter = try StreamFileWriter(url: dir.appendingPathComponent("track.bin"))
            heartWriter = try StreamFileWriter(url: dir.appendingPathComponent("heart.bin"))
            accelWriter = try StreamFileWriter(url: dir.appendingPathComponent("accel.bin"))
            // Written NOW, so an interrupted session is still recoverable. See `SessionPaths`.
            try writeMeta(meta(id: id, start: now, durationS: 0), to: dir)
            directory = dir
        } catch {
            Self.log.error("could not open the session files: \(error.localizedDescription)")
            phase = .failed("Could not start recording — no space on the watch?")
            return
        }

        sessionId = id
        startDate = now
        startUptime = ProcessInfo.processInfo.systemUptime
        speedMps = 0
        maxSpeedMps = 0
        distanceM = 0
        heartRateBpm = nil
        elapsedS = 0
        pendingGap = false
        lastFixLatLon = nil

        do {
            try makeWorkoutBridge().start(at: now)
        } catch {
            Self.log.error("could not start the workout session: \(error.localizedDescription)")
            phase = .failed("Apple Health would not start a workout.")
            closeWriters()
            return
        }

        location?.startUpdating(background: true)
        // The handler captures the writer, the clock origin and the gate directly — never
        // `self`. Nothing on this path touches the main actor, which is the only way a 50 Hz
        // sensor and a SwiftUI view can share a process without one of them suffering.
        accelGate.set(true)
        if let accelWriter {
            let gate = accelGate
            let origin = startUptime
            motion.start { uptime, magnitude in
                guard gate.isOpen else { return }
                let sample = WatchAccelSample(t: uptime - origin, magnitudeG: magnitude)
                accelWriter.append(WatchSessionContainer.encodeRecord(sample))
            }
        }

        // Water lock on at start, not offered as a choice: the rider is about to put this
        // wrist in Lake Garda, and a screen that responds to water is a screen that stops the
        // recording by itself. The crown unlocks it.
        WKInterfaceDevice.current().enableWaterLock()

        phase = .recording
        startTicker()
        Self.log.info("recording \(id) started")
    }

    // MARK: - Pause / resume / stop

    func pause() {
        guard phase == .recording else { return }
        phase = .paused
        workout?.pause()
        accelGate.set(false)
        speedMps = 0
        Self.log.info("recording paused")
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .recording
        workout?.resume()
        accelGate.set(true)
        // The next fix opens a new segment: the two sides of a pause are not one motion, and
        // a speed differentiated across the join would be a fiction.
        pendingGap = true
        lastFixLatLon = nil
        WKInterfaceDevice.current().enableWaterLock()
        Self.log.info("recording resumed")
    }

    func stop() {
        guard phase == .recording || phase == .paused else { return }
        phase = .saving
        stopTicker()

        let end = Date()
        let duration = end.timeIntervalSince(startDate)
        accelGate.set(false)
        motion.stop()
        location?.stopUpdating()
        location?.startUpdating(background: false)

        let counts = closeWriters()
        let dir = directory
        let id = sessionId
        let started = startDate

        Task {
            await workout?.end(at: end)
            workout = nil
            let queued = assembleAndQueue(id: id, start: started, durationS: duration,
                                          directory: dir)
            summary = RecordedSummary(durationS: duration,
                                      distanceM: distanceM,
                                      maxSpeedMps: maxSpeedMps,
                                      trackCount: counts.track,
                                      heartCount: counts.heart,
                                      accelCount: counts.accel,
                                      queuedForTransfer: queued)
            phase = .finished
            Self.log.info("""
                recording \(id) finished: \(counts.track) fixes, \(counts.heart) hr, \
                \(counts.accel) accel, queued=\(queued)
                """)
        }
    }

    func dismissSummary() {
        summary = nil
        phase = .idle
    }

    // MARK: - Sensor handling

    private func handle(authorization status: CLAuthorizationStatus) {
        locationAuthorization = status
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            location?.startUpdating(background: phase == .recording)
        }
    }

    private func handle(_ fix: Fix) {
        fixAccuracyM = fix.horizontalAccuracyM
        lastFixAt = Date()

        guard phase == .recording else { return }
        let t = fix.timestamp.timeIntervalSince(startDate)
        // CoreLocation happily hands over a cached fix from before the session began. It
        // belongs to a different afternoon's arithmetic.
        guard t >= 0 else { return }

        let sample = WatchTrackSample(t: t, lat: fix.lat, lon: fix.lon,
                                      speedMps: fix.speedMps,
                                      horizontalAccuracyM: fix.horizontalAccuracyM,
                                      altitudeM: fix.altitudeM,
                                      gapBefore: pendingGap)
        pendingGap = false
        trackWriter?.append(WatchSessionContainer.encodeRecord(sample))

        if let speed = fix.speedMps {
            speedMps = speed
            maxSpeedMps = max(maxSpeedMps, speed)
        }
        accumulateDistance(to: fix)
    }

    /// The live distance readout, on the same equirectangular projection the phone's
    /// `TrackCleaner` uses. It is a *display*: the phone re-derives distance from the track
    /// with the cleaner's gates applied, and that number is the one the library keeps.
    private func accumulateDistance(to fix: Fix) {
        defer { lastFixLatLon = (fix.lat, fix.lon) }
        guard let last = lastFixLatLon else { return }
        let dx = (fix.lon - last.lon) * cos(fix.lat * .pi / 180) * 111_320
        let dy = (fix.lat - last.lat) * 110_540
        distanceM += (dx * dx + dy * dy).squareRoot()
    }

    private func handle(heartRateAt at: Date, bpm: Double) {
        heartRateBpm = bpm
        guard phase == .recording else { return }
        let t = at.timeIntervalSince(startDate)
        guard t >= 0 else { return }
        heartWriter?.append(WatchSessionContainer.encodeRecord(WatchHeartSample(t: t, bpm: bpm)))
    }

    private func workoutFailed(_ message: String) {
        guard phase == .recording || phase == .paused else { return }
        Self.log.error("workout ended unexpectedly: \(message)")
        // Do not throw the session away — stop cleanly, which assembles and queues whatever
        // was captured before things went wrong.
        stop()
    }

    // MARK: - Assembly

    @discardableResult
    private func closeWriters() -> (track: Int, heart: Int, accel: Int) {
        let track = trackWriter?.close().records ?? 0
        let heart = heartWriter?.close().records ?? 0
        let accel = accelWriter?.close().records ?? 0
        trackWriter = nil
        heartWriter = nil
        accelWriter = nil
        return (track, heart, accel)
    }

    private func meta(id: String, start: Date, durationS: Double) -> WatchSessionMeta {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let device = WKInterfaceDevice.current()
        return WatchSessionMeta(sessionId: id,
                                startEpoch: start.timeIntervalSince1970,
                                utcOffsetS: TimeZone.current.secondsFromGMT(for: start),
                                durationS: durationS,
                                activityType: "surfingSports",
                                locationRateHz: 1,
                                accelRateHz: MotionSampler.rateHz,
                                producer: "CleanJibe watchOS \(version) (\(build))",
                                device: device.model,
                                systemVersion: device.systemVersion)
    }

    private func writeMeta(_ meta: WatchSessionMeta, to directory: URL) throws {
        let data = try JSONEncoder().encode(meta)
        try data.write(to: directory.appendingPathComponent("meta.json"), options: .atomic)
    }

    /// Builds the container from the stream files and hands it to WatchConnectivity.
    private func assembleAndQueue(id: String, start: Date, durationS: Double,
                                  directory: URL?) -> Bool {
        guard let directory else { return false }
        do {
            let file = try assemble(id: id, start: start, durationS: durationS,
                                    directory: directory)
            let queued = SessionTransfer.shared.send(file.url, meta: file.meta)
            // The raw streams have done their job; the container carries everything.
            try? FileManager.default.removeItem(at: directory)
            self.directory = nil
            return queued
        } catch {
            Self.log.error("could not assemble \(id): \(error.localizedDescription)")
            phase = .failed("Could not save the session file.")
            return false
        }
    }

    private func assemble(id: String, start: Date, durationS: Double,
                          directory: URL) throws -> (url: URL, meta: WatchSessionMeta) {
        let trackBytes = (try? Data(contentsOf: directory.appendingPathComponent("track.bin"))) ?? Data()
        let heartBytes = (try? Data(contentsOf: directory.appendingPathComponent("heart.bin"))) ?? Data()
        let accelBytes = (try? Data(contentsOf: directory.appendingPathComponent("accel.bin"))) ?? Data()

        let meta = meta(id: id, start: start, durationS: durationS)
        let container = try WatchSessionContainer.assemble(meta: meta,
                                                           trackBytes: trackBytes,
                                                           heartBytes: heartBytes,
                                                           accelBytes: accelBytes)
        let url = try SessionPaths.outbox().appendingPathComponent("\(id).cjw")
        try container.write(to: url, options: .atomic)
        return (url, meta)
    }

    // MARK: - Recovery

    /// Assembles and queues anything left behind by a session that never got to stop.
    ///
    /// watchOS kills apps for memory, batteries go flat, and a rider who spent two hours on
    /// the water should not lose them to either. `meta.json` was written at start, and the
    /// stream files are valid as far as they go, so everything needed is on disk.
    private func recoverInterruptedSessions() {
        guard let root = try? SessionPaths.recordings(),
              let directories = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil) else { return }
        for directory in directories where directory.lastPathComponent != sessionId {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("meta.json")),
                  let meta = try? JSONDecoder().decode(WatchSessionMeta.self, from: data) else {
                // No meta: nothing here can be placed on a timeline. Reclaim the space.
                Self.log.error("discarding unrecoverable recording \(directory.lastPathComponent)")
                try? FileManager.default.removeItem(at: directory)
                continue
            }
            // The last fix is what the session actually got to, which is a better duration
            // than the zero written at start.
            let trackURL = directory.appendingPathComponent("track.bin")
            let bytes = (try? Data(contentsOf: trackURL))?.count ?? 0
            let duration = Double(bytes / WatchSessionContainer.trackRecordBytes)
            guard duration > 0 else {
                try? FileManager.default.removeItem(at: directory)
                continue
            }
            Self.log.info("recovering interrupted session \(meta.sessionId) (~\(Int(duration)) s)")
            do {
                _ = try assemble(id: meta.sessionId,
                                 start: Date(timeIntervalSince1970: meta.startEpoch),
                                 durationS: duration,
                                 directory: directory)
                try? FileManager.default.removeItem(at: directory)
            } catch {
                Self.log.error("could not recover \(meta.sessionId): \(error.localizedDescription)")
            }
        }
    }

    /// Queues everything sitting in the outbox.
    ///
    /// `transferFile` persists its own queue across launches, so most of what is here is
    /// already in flight — `SessionTransfer.send` checks that and skips it. What this catches
    /// is the rest: a session recovered from a crash a moment ago, and any file whose
    /// transfer the system eventually abandoned.
    private func sweepOutbox() {
        guard let outbox = try? SessionPaths.outbox(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: outbox, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == WatchSessionContainer.fileExtension {
            guard let data = try? Data(contentsOf: file),
                  let header = try? WatchSessionContainer.header(data) else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            Self.log.info("re-queuing \(file.lastPathComponent)")
            SessionTransfer.shared.send(file, meta: header.meta)
        }
    }

    // MARK: - Elapsed clock

    private func startTicker() {
        stopTicker()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.phase == .recording || self.phase == .paused {
                    self.elapsedS = Date().timeIntervalSince(self.startDate)
                }
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
