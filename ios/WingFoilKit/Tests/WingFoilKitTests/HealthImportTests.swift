import Foundation
import Testing
@testable import WingFoilKit

/// `HealthImport` — a workout recorded with **Apple's own Workout app**, read back out of
/// Health and turned into the same `RawTrack` every other source produces
/// (docs/decisions.md ADR-017).
///
/// **Nothing here touches HealthKit.** The kit has no Health database, no entitlement and no
/// watch in the room, which is exactly why the mapper takes plain value types: everything
/// below is arithmetic on a synthetic afternoon, and the app layer's job is reduced to
/// filling those structs from `CLLocation`s.
struct HealthImportTests {

    // MARK: - Fixture

    /// Thirty minutes shaped like a real session, at Apple's nominal 1 Hz:
    ///
    /// * 0–119 s   drifting at 1 m/s — below the flight entry speed, so not flying
    /// * 120–719 s a straight run east at 11 m/s (flight 1)
    /// * 720–725 s a 180° turn over 6 s at 8 m/s — 30°/s peak, a 15 m radius, well inside
    ///             every `TurnConfig` gate
    /// * 726–1319 s the straight run back west (still flight 1 unless the turn broke it)
    /// * 1320–1439 s stopped at 0.2 m/s — the flight ends here
    /// * 1440–1499 s **missing**: the rider paused, and Health simply has no fixes
    /// * 1500–1799 s riding again at 11 m/s (flight 2)
    ///
    /// Positions are integrated from heading and speed rather than written down, because COG
    /// is derived from the *positions* by `TrackCleaner` — a track whose speed channel and
    /// whose geometry disagreed would test neither.
    static func route(start: Date = Date(timeIntervalSince1970: 1_756_000_000),
                      withGap: Bool = true) -> [HealthRouteSample] {
        var samples: [HealthRouteSample] = []
        var lat = 45.8722, lon = 10.8747
        let metresPerDegLat = 110_540.0
        let metresPerDegLon = 111_320.0 * cos(45.8722 * .pi / 180)

        for second in 0..<1800 {
            if withGap, (1440..<1500).contains(second) { continue }
            let t = Double(second)
            let speed: Double
            var headingDeg: Double
            switch second {
            case 0..<120:
                speed = 1.0
                headingDeg = 90
            case 120..<720:
                speed = 11.0
                headingDeg = 90
            case 720..<726:
                speed = 8.0
                headingDeg = 90 + 30 * Double(second - 720)     // 90° → 240°
            case 726..<1320:
                speed = 11.0
                headingDeg = 270
            case 1320..<1440:
                speed = 0.2
                headingDeg = 270
            default:
                speed = 11.0
                headingDeg = 90
            }
            headingDeg = headingDeg.truncatingRemainder(dividingBy: 360)
            let radians = headingDeg * .pi / 180
            samples.append(HealthRouteSample(timestamp: start.addingTimeInterval(t),
                                             lat: lat, lon: lon,
                                             altitudeM: 0.5,
                                             horizontalAccuracyM: 4.5,
                                             speedMps: speed,
                                             courseDeg: headingDeg))
            // Advance for the next fix: one second at this speed on this heading.
            lat += speed * cos(radians) / metresPerDegLat
            lon += speed * sin(radians) / metresPerDegLon
        }
        return samples
    }

    /// Heart rate every 3 s across the whole session, the way the sensor actually reports.
    static func heart(start: Date = Date(timeIntervalSince1970: 1_756_000_000))
    -> [HealthHeartSample] {
        stride(from: 0, to: 1800, by: 3).map {
            HealthHeartSample(timestamp: start.addingTimeInterval(Double($0)),
                              bpm: 134 + 14 * sin(Double($0) / 90))
        }
    }

    static func track(withGap: Bool = true, heart: [HealthHeartSample]? = nil,
                      utcOffsetS: Int? = nil) throws -> RawTrack {
        try HealthImport.track(sessionId: "health-fixture",
                               activityType: "surfingSports",
                               route: route(withGap: withGap),
                               heart: heart ?? Self.heart(),
                               utcOffsetS: utcOffsetS,
                               producer: "CleanJibe iOS test fixture (Apple Health)")
    }

    // MARK: - The mapping

    @Test func mapsARouteOntoOneClock() throws {
        let track = try Self.track()
        #expect(track.startDate == Date(timeIntervalSince1970: 1_756_000_000))
        #expect(track.samples.count == 1800 - 60)
        #expect(track.samples[0].t == 0)
        #expect(track.samples[10].timestamp == Date(timeIntervalSince1970: 1_756_000_010))
        #expect(track.samples.last?.t == 1799)
        #expect(track.samples.allSatisfy { $0.lat != nil && $0.lon != nil })
        // Distance stays the engine's to compute, as it does for every source: Health hands
        // over no odometer, and a second answer in that column would only ever disagree.
        #expect(track.samples.allSatisfy { $0.distanceM == nil })
    }

    /// **The capability decision, asserted rather than described.** Apple's route speed is
    /// `CLLocation.speed` — the GNSS chip's own Doppler solution — so these sessions certify,
    /// exactly as ADR-016 already settled for the CleanJibe watch app. What they do *not*
    /// have is an accelerometer, and the letter says so by staying plain (b).
    @Test func speedIsDopplerSoTheSessionCertifies() throws {
        let caps = try Self.track().capabilities

        #expect(caps.hasSpeed)
        #expect(caps.hasPosition)
        #expect(caps.hasHR)
        #expect(!caps.hasAccel)                  // nothing recorded the wrist
        #expect(!caps.hasDevFields)              // nothing of ours ever reached this workout
        #expect(!caps.hasWatchLaps)
        #expect(caps.sourceClass == "b")         // certified — NOT a GPX's class (c)
        #expect(abs(caps.sampleRateHz - 1) < 0.001)
        // What Health actually holds, and what the rider actually did — two different facts,
        // kept in two different fields.
        #expect(caps.sport == "surfingSports")
        #expect(caps.discipline == "wingfoil")
    }

    @Test func heartRateIsJoinedOntoTheRecordTimeline() throws {
        let track = try Self.track()
        #expect(track.capabilities.hasHR)
        // Readings arrive every 3 s and join inside the ±5 s tolerance, so every record has
        // one — which is what the HR-cost metrics need to run at all.
        #expect(track.samples.allSatisfy { $0.heartRate != nil })
        #expect(track.samples[0].heartRate.map { abs($0 - 134) < 0.001 } == true)

        let none = try Self.track(heart: [])
        #expect(!none.capabilities.hasHR)
        #expect(none.samples.allSatisfy { $0.heartRate == nil })
        #expect(none.capabilities.sourceClass == "b")   // the speed channel still certifies
    }

    /// A reading from before the first fix or after the last is not this track's heart rate.
    /// Health hands back the whole workout's samples, warm-up included.
    @Test func heartRateOutsideTheRoutesSpanIsDropped() throws {
        let start = Date(timeIntervalSince1970: 1_756_000_000)
        let strays = [HealthHeartSample(timestamp: start.addingTimeInterval(-600), bpm: 70),
                      HealthHeartSample(timestamp: start.addingTimeInterval(9_000), bpm: 70)]
        let payload = try HealthImport.payload(sessionId: "x", activityType: "surfingSports",
                                               route: Self.route(),
                                               heart: Self.heart() + strays,
                                               utcOffsetS: nil, producer: "test")
        #expect(payload.heart.count == Self.heart().count)
        #expect(payload.heart.allSatisfy { $0.t >= -5 && $0.t <= 1799 + 5 })
    }

    @Test func aTimestampJumpIsMarkedAsADeclaredBreak() throws {
        let track = try Self.track()
        let gaps = track.samples.enumerated().filter { $0.element.gapBefore }
        #expect(gaps.count == 1)
        // The first fix after the missing minute, and nothing else.
        #expect(gaps.first?.element.t == 1500)

        // The same session without the pause declares nothing at all.
        #expect(try Self.track(withGap: false).samples.allSatisfy { !$0.gapBefore })
    }

    @Test func anEmptyRouteIsRejectedRatherThanImportedAsNothing() throws {
        #expect(throws: HealthImport.ImportError.noRoute) {
            try HealthImport.track(sessionId: "x", activityType: "surfingSports",
                                   route: [], heart: Self.heart(), producer: "test")
        }
        // A workout whose every fix is unusable is the same case wearing a disguise.
        let broken = [HealthRouteSample(timestamp: Date(), lat: .nan, lon: 10)]
        #expect(throws: HealthImport.ImportError.noRoute) {
            try HealthImport.track(sessionId: "x", activityType: "surfingSports",
                                   route: broken, producer: "test")
        }
    }

    /// CoreLocation says "no reading" with a negative number, and it must never reach the
    /// engine as one: -1 m/s inside a record window is a real number to the analysis and
    /// nonsense to the rider.
    @Test func negativeCoreLocationSentinelsBecomeNil() throws {
        let start = Date(timeIntervalSince1970: 1_756_000_000)
        let route = (0..<10).map {
            HealthRouteSample(timestamp: start.addingTimeInterval(Double($0)),
                              lat: 45.87, lon: 10.87 + Double($0) * 1e-4,
                              horizontalAccuracyM: -1, speedMps: -1)
        }
        let payload = try HealthImport.payload(sessionId: "x", activityType: "surfingSports",
                                               route: route, utcOffsetS: nil, producer: "test")
        #expect(payload.track.allSatisfy { $0.speedMps == nil })
        #expect(payload.track.allSatisfy { $0.horizontalAccuracyM == nil })
        // With no speed on any fix the source cannot claim the channel, and the honest
        // consequence is class (c) — the same rule the container already applies to itself.
        #expect(try WatchSessionParser.build(payload).capabilities.sourceClass == "c")
    }

    @Test func unsortedAndRepeatedFixesAreNormalised() throws {
        let start = Date(timeIntervalSince1970: 1_756_000_000)
        let one = HealthRouteSample(timestamp: start, lat: 45.87, lon: 10.87, speedMps: 5)
        let two = HealthRouteSample(timestamp: start.addingTimeInterval(1),
                                    lat: 45.8701, lon: 10.87, speedMps: 5)
        let cleaned = HealthImport.usable([two, one, one])
        #expect(cleaned.count == 2)
        #expect(cleaned[0].timestamp == start)
    }

    // MARK: - The session's clock

    /// Rung 1 of `SessionIngestor.resolveUtcOffset` when — and only when — the workout said
    /// so itself. Apple's Workout app usually does not, and a device-zone guess wearing an
    /// exact answer's provenance would license every surface in the app to state a clock it
    /// does not know.
    @Test func anOffsetIsClaimedOnlyWhenTheWorkoutStatedOne() throws {
        let stated = try Self.track(utcOffsetS: 7200)
        #expect(stated.startUtcOffsetS == 7200)
        #expect(stated.startUtcOffsetSource == .activity)
        #expect(stated.startUtcOffsetSource?.isExact == true)

        let silent = try Self.track()
        #expect(silent.startUtcOffsetS == nil)
        #expect(silent.startUtcOffsetSource == nil)
        // The ladder then answers, and records that it guessed.
        let resolved = SessionIngestor.resolveUtcOffset(track: silent, fallback: nil)
        #expect(resolved.source == .longitude)
        #expect(resolved.source.isExact == false)
    }

    /// Every container the watch app has ever written omits the flag, and must keep meaning
    /// "the recording said so itself".
    @Test func anOlderContainerWithoutTheFlagStillClaimsRungOne() throws {
        let track = try WatchSessionParser.parse(data: WatchImportTests.fixtureData(minutes: 1))
        #expect(track.startUtcOffsetS == 7200)
        #expect(track.startUtcOffsetSource == .activity)
    }

    // MARK: - The container, and the archive

    /// The mapper and the archived bytes must produce the *same* track, or a session would
    /// change its numbers at the next engine bump. They do by construction — `track` is
    /// `WatchSessionParser.build` over the same payload — and this is that construction
    /// asserted rather than trusted.
    @Test func theContainerRoundTripsToTheSameTrack() throws {
        let data = try HealthImport.container(sessionId: "health-fixture",
                                              activityType: "surfingSports",
                                              route: Self.route(), heart: Self.heart(),
                                              utcOffsetS: 7200,
                                              producer: "CleanJibe iOS test fixture")
        #expect(TrackParser.format(data) == .watch)

        let direct = try Self.track(utcOffsetS: 7200)
        let reread = try TrackParser.parse(data: data)
        #expect(reread.samples.count == direct.samples.count)
        #expect(reread.capabilities == direct.capabilities)
        #expect(reread.startUtcOffsetS == direct.startUtcOffsetS)
        for (a, b) in zip(direct.samples, reread.samples) {
            #expect(a.t == b.t)
            #expect(a.lat == b.lat)
            #expect(a.gapBefore == b.gapBefore)
            // Speed and heart rate narrow to Float on the wire — the format's documented trade.
            #expect(abs((a.speedMps ?? 0) - (b.speedMps ?? 0)) < 1e-4)
            #expect(abs((a.heartRate ?? 0) - (b.heartRate ?? 0)) < 1e-3)
        }
    }

    @Test func theHeaderRecordsWhoWroteItAndWhatItKnew() throws {
        let data = try HealthImport.container(sessionId: "abc", activityType: "waterSports",
                                              route: Self.route(withGap: false),
                                              utcOffsetS: nil,
                                              producer: "CleanJibe iOS 0.14.0 (Apple Health)")
        let header = try WatchSessionContainer.header(data)
        // The format is `.cjw` and the *producer* is the phone: `TrackFormat.watch` names a
        // packed track layout, never who filled it in.
        #expect(header.meta.producer == "CleanJibe iOS 0.14.0 (Apple Health)")
        #expect(header.meta.activityType == "waterSports")
        #expect(header.meta.discipline == "wingfoil")
        #expect(header.meta.utcOffsetKnown == false)
        #expect(header.meta.accelRateHz == 0)
        #expect(abs(header.meta.locationRateHz - 1) < 0.001)
        #expect(header.streams.first { $0.name == "accel" }?.count == 0)
    }

    @Test func theFilenameNamesTheAfternoonItRecords() {
        let name = HealthImport.filename(start: Date(timeIntervalSince1970: 1_756_000_000),
                                         utcOffsetS: 7200)
        // 01:46 UTC, which is 03:46 on the clock the session was ridden on — the name is the
        // rider's afternoon, not the reader's.
        #expect(name == "2025-08-24-0346-health.cjw")
    }

    // MARK: - Analysis

    /// The point of all of it: a workout recorded with a stock Apple Watch and Apple's own
    /// app analyses like a native Garmin file — flights, turns and certified speed records.
    @Test func theEngineFindsFlightsAndTurnsInAnAppleWorkout() throws {
        let analysis = SessionSummarizer.analyze(try Self.track())

        #expect(analysis.capabilities.hasDoppler)        // the flag `certified` is built on
        #expect(!analysis.capabilities.hasAccel)
        #expect(analysis.capabilities.hasHR)
        #expect(analysis.engineVersion == AnalysisEngine.version)

        // Two rides either side of a 2-minute stop, and the 180° turn between them.
        #expect(analysis.flights.count >= 2)
        #expect(analysis.turns.count >= 1)
        #expect(analysis.summary.foilTimeS > 900)
        #expect((analysis.records.best2sKn ?? 0) > 18)   // 11 m/s ≈ 21 kn
    }

    // MARK: - All the way into the library

    private func makeIngestor() throws -> (SessionIngestor, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("health-ingest-\(UUID().uuidString)/Sessions",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (SessionIngestor(database: try AppDatabase.inMemory(),
                                archive: SessionArchive(root: root)), root)
    }

    /// The whole integration in one test: the app hands `SessionIngestor` the mapped bytes and
    /// nothing else changes — same door, same ±60 s dedupe, same archive, same re-analysis.
    @Test func aHealthWorkoutImportsThroughTheOrdinaryDoor() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let data = try HealthImport.container(sessionId: "abc", activityType: "surfingSports",
                                              route: Self.route(), heart: Self.heart(),
                                              utcOffsetS: 7200, producer: "test")

        let summary = await ingestor.ingestContainer(data: data,
                                                     name: "2026-08-24-0546-health.cjw",
                                                     source: .appleHealth)
        #expect(summary.imported == 1)
        #expect(summary.failed.isEmpty)

        let row = try #require(try await ingestor.allSessions().first)
        #expect(row.importSource == "applehealth")
        #expect(row.sourceClass == "b")
        #expect(row.discipline == "wingfoil")
        #expect(row.startUtcOffsetSource == UtcOffsetSource.activity.rawValue)
        #expect(ingestor.archive.originalFormat(for: row.id) == .watch)

        // The engine bump path — without an archived original these sessions would lose every
        // number the first time the engine changed.
        let reanalysed = try await ingestor.reanalyze(row)
        #expect(reanalysed.capabilities.hasDoppler)
        #expect(!reanalysed.capabilities.hasAccel)

        // Importing the same workout twice — the automatic pickup racing a manual import —
        // is one session, not two.
        let again = await ingestor.ingestContainer(data: data, name: "again.cjw",
                                                   source: .appleHealth)
        #expect(again.duplicates == 1)
        #expect(try await ingestor.allSessions().count == 1)
    }

    /// The provenance tags for the three things this app calls "watch" have to stay apart:
    /// a Garmin BLE card, a CleanJibe watch recording, and a workout somebody else's app
    /// wrote into Health.
    @Test func healthProvenanceStaysApartFromTheOtherTwo() {
        #expect(ImportSource.appleHealth.rawValue == "applehealth")
        #expect(ImportSource.appleHealth.isNamed(in: "applehealth+icu"))
        #expect(!ImportSource.appleHealth.isNamed(in: "applewatch"))
        #expect(!ImportSource.appleWatch.isNamed(in: "applehealth"))
        #expect(!ImportSource.watch.isNamed(in: "applehealth"))
        #expect(SessionIngestor.merge(sources: "applehealth", adding: .icu) == "applehealth+icu")
    }

    @Test func aHealthWorkoutPassesTheWatersportGate() throws {
        // `surfingSports` is not in the FIT sport allow-list; the discipline tag is what gets
        // one through, exactly as our own developer fields do.
        #expect(SessionIngestor.isWatersport(try Self.track().capabilities))
    }
}
