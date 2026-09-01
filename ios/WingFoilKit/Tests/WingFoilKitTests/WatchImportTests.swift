import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// The watch container (docs/watch-session-schema.md) and the `WatchImport` path that turns
/// one into a `RawTrack`.
///
/// **Every fixture here is synthesised in-test.** Nothing reads a real recording: the whole
/// point of these tests is that the *format* round-trips and that the capabilities come out
/// honest, and both are properties of the code rather than of anybody's afternoon.
struct WatchImportTests {

    // MARK: - Fixture

    /// A synthetic session: `minutes` of riding at 1 Hz, heart rate every 3 s, accelerometer
    /// at 50 Hz. Positions walk east from Torbole at a speed that oscillates, so the track is
    /// long enough to survive the cleaner and varied enough to be a plausible input.
    static func fixture(minutes: Double = 4,
                        startEpoch: Double = 1_756_000_000,
                        utcOffsetS: Int = 7200,
                        withHeart: Bool = true,
                        withAccel: Bool = true)
    -> (meta: WatchSessionMeta, track: [WatchTrackSample],
        heart: [WatchHeartSample], accel: [WatchAccelSample]) {
        let seconds = Int(minutes * 60)
        let lat0 = 45.8722, lon0 = 10.8747

        var track: [WatchTrackSample] = []
        var lat = lat0, lon = lon0
        for i in 0..<seconds {
            let t = Double(i)
            // 6–14 m/s, a slow oscillation: fast enough to fly, varied enough that the
            // record windows and the flight segmenter both have something to chew on.
            let speed = 10 + 4 * sin(t / 25)
            lon += speed / (111_320 * cos(lat0 * .pi / 180))
            lat += 0.000_001 * sin(t / 60)
            track.append(WatchTrackSample(t: t, lat: lat, lon: lon,
                                          speedMps: speed,
                                          horizontalAccuracyM: 4.5,
                                          altitudeM: 0.4,
                                          gapBefore: false))
        }

        var heart: [WatchHeartSample] = []
        if withHeart {
            for i in stride(from: 0, to: seconds, by: 3) {
                heart.append(WatchHeartSample(t: Double(i), bpm: 132 + 12 * sin(Double(i) / 40)))
            }
        }

        var accel: [WatchAccelSample] = []
        if withAccel {
            let n = seconds * 50
            for i in 0..<n {
                let t = Double(i) / 50
                // Gravity plus a 1.4 Hz pumping oscillation — the band `PumpConfig` looks in.
                accel.append(WatchAccelSample(t: t, magnitudeG: 1.0 + 0.5 * sin(2 * .pi * 1.4 * t)))
            }
        }

        let meta = WatchSessionMeta(sessionId: "11111111-2222-3333-4444-555555555555",
                                    startEpoch: startEpoch,
                                    utcOffsetS: utcOffsetS,
                                    durationS: Double(seconds),
                                    activityType: "surfingSports",
                                    producer: "CleanJibe watchOS test fixture")
        return (meta, track, heart, accel)
    }

    static func fixtureData(minutes: Double = 4, withHeart: Bool = true,
                            withAccel: Bool = true) throws -> Data {
        let f = fixture(minutes: minutes, withHeart: withHeart, withAccel: withAccel)
        return try WatchSessionContainer.encode(meta: f.meta, track: f.track,
                                                heart: f.heart, accel: f.accel)
    }

    // MARK: - Container round-trip

    @Test func containerRoundTripsEveryStream() throws {
        let f = Self.fixture()
        let data = try WatchSessionContainer.encode(meta: f.meta, track: f.track,
                                                    heart: f.heart, accel: f.accel)
        let back = try WatchSessionContainer.decode(data)

        #expect(back.meta == f.meta)
        #expect(back.track.count == f.track.count)
        #expect(back.heart.count == f.heart.count)
        #expect(back.accel.count == f.accel.count)

        // Doubles on the wire survive exactly; the Float-narrowed channels survive to
        // single precision, which is the trade the format documents.
        for (a, b) in zip(f.track, back.track) {
            #expect(a.t == b.t)
            #expect(a.lat == b.lat)
            #expect(a.lon == b.lon)
            #expect(abs((a.speedMps ?? 0) - (b.speedMps ?? 0)) < 1e-4)
            #expect(abs((a.horizontalAccuracyM ?? 0) - (b.horizontalAccuracyM ?? 0)) < 1e-4)
            #expect(a.gapBefore == b.gapBefore)
        }
        for (a, b) in zip(f.heart, back.heart) {
            #expect(a.t == b.t)
            #expect(abs(a.bpm - b.bpm) < 1e-3)
        }
        // Accel carries a Float time base — see the note on `encodeRecord(_: WatchAccelSample)`.
        for (a, b) in zip(f.accel, back.accel) {
            #expect(abs(a.t - b.t) < 1e-2)
            #expect(abs(a.magnitudeG - b.magnitudeG) < 1e-4)
        }
    }

    @Test func emptyOptionalChannelsComeBackNil() throws {
        let meta = Self.fixture().meta
        let sparse = WatchTrackSample(t: 0, lat: 45.8, lon: 10.8,
                                      speedMps: nil, horizontalAccuracyM: nil, altitudeM: nil,
                                      gapBefore: true)
        let data = try WatchSessionContainer.encode(meta: meta, track: [sparse],
                                                    heart: [], accel: [])
        let back = try WatchSessionContainer.decode(data)
        #expect(back.track.count == 1)
        #expect(back.track[0].speedMps == nil)
        #expect(back.track[0].horizontalAccuracyM == nil)
        #expect(back.track[0].altitudeM == nil)
        #expect(back.track[0].gapBefore)
        #expect(back.heart.isEmpty)
        #expect(back.accel.isEmpty)
    }

    /// CoreLocation reports "no reading" with a negative number. It must never reach the
    /// phone as one — a speed of -1 m/s in a record window would be a real number to the
    /// engine and a nonsense one to the rider.
    @Test func negativeCoreLocationSentinelsBecomeNil() throws {
        let meta = Self.fixture().meta
        let invalid = WatchTrackSample(t: 0, lat: 45.8, lon: 10.8,
                                       speedMps: -1, horizontalAccuracyM: -1)
        let data = try WatchSessionContainer.encode(meta: meta, track: [invalid],
                                                    heart: [], accel: [])
        let back = try WatchSessionContainer.decode(data)
        #expect(back.track[0].speedMps == nil)
        #expect(back.track[0].horizontalAccuracyM == nil)
    }

    @Test func headerReadsWithoutDecodingStreams() throws {
        let data = try Self.fixtureData()
        let header = try WatchSessionContainer.header(data)
        #expect(header.meta.discipline == "wingfoil")
        #expect(header.meta.activityType == "surfingSports")
        #expect(header.streams.count == 3)
        #expect(header.streams.contains { $0.name == "accel" && $0.count == 4 * 60 * 50 })
    }

    @Test func rejectsForeignBytes() throws {
        #expect(!WatchSessionContainer.isContainer(Data("<gpx></gpx>".utf8)))
        #expect(!WatchSessionContainer.isContainer(Data()))
        #expect(throws: WatchSessionContainer.Error.notAContainer) {
            try WatchSessionContainer.header(Data("<gpx/>".utf8))
        }
    }

    /// A transfer cut short still contains real riding. The header promises more records than
    /// arrived; the decoder reads what is there rather than throwing the session away.
    @Test func truncatedStreamsAreReadAsFarAsTheyGo() throws {
        let data = try Self.fixtureData(minutes: 2)
        let cut = data.prefix(data.count - 5000)
        let back = try WatchSessionContainer.decode(Data(cut))
        #expect(!back.track.isEmpty)
        #expect(back.accel.count < 2 * 60 * 50)
    }

    @Test func rejectsAFutureContainerVersion() throws {
        var data = try Self.fixtureData(minutes: 1)
        data[4] = 99
        #expect(throws: WatchSessionContainer.Error.unsupportedVersion(99)) {
            try WatchSessionContainer.header(data)
        }
    }

    /// `assemble` derives counts from byte lengths, so a stream file whose last record was
    /// half-written when the app died loses the ragged tail instead of promising a record
    /// that is not there.
    @Test func assembleDropsAPartialTrailingRecord() throws {
        let f = Self.fixture(minutes: 1)
        var accelBytes = Data()
        for s in f.accel.prefix(10) { accelBytes.append(WatchSessionContainer.encodeRecord(s)) }
        accelBytes.append(contentsOf: [0x01, 0x02, 0x03])       // a torn record
        let data = try WatchSessionContainer.assemble(meta: f.meta, trackBytes: Data(),
                                                      heartBytes: Data(), accelBytes: accelBytes)
        let back = try WatchSessionContainer.decode(data)
        #expect(back.accel.count == 10)
    }

    // MARK: - Container to RawTrack

    @Test func parsesIntoARawTrackWithHonestCapabilities() throws {
        let track = try WatchSessionParser.parse(data: Self.fixtureData())
        let caps = track.capabilities

        #expect(caps.hasSpeed)                       // CLLocation.speed — Doppler, class (b)
        #expect(caps.hasPosition)
        #expect(caps.hasHR)
        #expect(caps.hasAccel)                       // 50 Hz, so pump analysis runs
        #expect(!caps.hasDevFields)                  // the MVP records, it does not detect
        #expect(!caps.hasWatchLaps)
        #expect(caps.discipline == "wingfoil")
        #expect(caps.sport == "surfingSports")
        #expect(abs(caps.sampleRateHz - 1) < 0.001)

        // THE records decision, asserted rather than described: a watch session certifies.
        #expect(caps.sourceClass == "b")
        #expect(track.watchSummary.isEmpty)
    }

    @Test func carriesTheWatchsOwnUtcOffsetAsAnExactAnswer() throws {
        let track = try WatchSessionParser.parse(data: Self.fixtureData())
        #expect(track.startUtcOffsetS == 7200)
        // Rung 1: the recording said so itself, so no surface has to hedge the clock.
        #expect(track.startUtcOffsetSource == .activity)
        #expect(track.startUtcOffsetSource?.isExact == true)
    }

    @Test func samplesLandOnOneClockWithHeartRateJoined() throws {
        let track = try WatchSessionParser.parse(data: Self.fixtureData())
        #expect(track.samples.count == 240)
        #expect(track.startDate == Date(timeIntervalSince1970: 1_756_000_000))
        #expect(track.samples[0].t == 0)
        #expect(track.samples[10].timestamp == Date(timeIntervalSince1970: 1_756_000_010))
        // HR arrives every 3 s and joins within the 5 s tolerance, so every record has one.
        #expect(track.samples.allSatisfy { $0.heartRate != nil })
        // Distance is the engine's to compute; the watch carries no odometer.
        #expect(track.samples.allSatisfy { $0.distanceM == nil })
        #expect(track.accel.count == 240 * 50)
    }

    /// A stale reading is not this record's heart rate. Better absent than stretched.
    @Test func heartRateBeyondToleranceIsLeftOff() throws {
        var cursor = 0
        let heart = [WatchHeartSample(t: 0, bpm: 140)]
        #expect(WatchSessionParser.heartRate(at: 2, in: heart, cursor: &cursor) == 140)
        cursor = 0
        #expect(WatchSessionParser.heartRate(at: 60, in: heart, cursor: &cursor) == nil)
        cursor = 0
        #expect(WatchSessionParser.heartRate(at: 0, in: [], cursor: &cursor) == nil)
    }

    @Test func aSessionWithoutHeartOrAccelDegradesRatherThanFailing() throws {
        let data = try Self.fixtureData(minutes: 2, withHeart: false, withAccel: false)
        let track = try WatchSessionParser.parse(data: data)
        #expect(!track.capabilities.hasHR)
        #expect(!track.capabilities.hasAccel)
        #expect(track.accel.isEmpty)
        #expect(track.samples.allSatisfy { $0.heartRate == nil })
        // Still class (b): the speed channel is what certifies, and it is still there.
        #expect(track.capabilities.sourceClass == "b")
    }

    @Test func aPauseSurvivesAsADeclaredBreak() throws {
        var f = Self.fixture(minutes: 2)
        f.track[80].gapBefore = true
        let data = try WatchSessionContainer.encode(meta: f.meta, track: f.track,
                                                    heart: f.heart, accel: f.accel)
        let track = try WatchSessionParser.parse(data: data)
        #expect(track.samples[80].gapBefore)
        #expect(track.samples.filter(\.gapBefore).count == 1)
    }

    @Test func aContainerWithNoFixesThrowsRatherThanImportingNothing() throws {
        let meta = Self.fixture().meta
        let data = try WatchSessionContainer.encode(meta: meta, track: [], heart: [], accel: [])
        #expect(throws: WatchSessionParser.ParseError.noRecords) {
            try WatchSessionParser.parse(data: data)
        }
    }

    // MARK: - The one door

    /// The whole integration in one assertion: `TrackParser` recognises the container by its
    /// bytes, so every caller that already handles a FIT or a GPX handles a watch session
    /// with no change at all — including the archive's re-analysis path.
    @Test func trackParserRecognisesTheContainerByItsBytes() throws {
        let data = try Self.fixtureData(minutes: 1)
        #expect(TrackParser.format(data) == .watch)
        #expect(TrackFormat.watch.fileExtension == "cjw")
        let track = try TrackParser.parse(data: data)
        #expect(track.capabilities.sourceClass == "b")
    }

    @Test func theArchiveStoresAndReReadsAWatchSession() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("watch-archive-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = SessionArchive(root: root)
        let data = try Self.fixtureData(minutes: 1)

        try archive.storeOriginal(data, id: "session-1")
        #expect(archive.originalURL(for: "session-1").lastPathComponent == "original.cjw")
        #expect(archive.originalFormat(for: "session-1") == .watch)
        // Re-analysis re-parses the archived original; without this the session would lose
        // every number at the next engine bump.
        let reread = try archive.rawTrack(for: "session-1")
        #expect(reread.samples.count == 60)
        #expect(reread.capabilities.hasAccel)
    }

    // MARK: - Analysis

    /// The reason the accelerometer is on the wire at all: with it, a watch session gets the
    /// pump analysis a native Garmin FIT cannot have.
    @Test func pumpAnalysisRunsOnAWatchSession() throws {
        let track = try WatchSessionParser.parse(data: Self.fixtureData(minutes: 2))
        let pump = PumpAnalyzer.track(track)
        #expect(pump != nil)
        // The fixture oscillates at 1.4 Hz, inside PumpConfig's 0.5–2.5 Hz band.
        #expect((pump?.strokes(from: 10, to: 30).count ?? 0) > 5)
    }

    /// End to end, the way the app will actually see it: bytes in, a full `SessionAnalysis`
    /// out, with the source flags the rest of the app reads off it.
    @Test func theEngineAnalysesAWatchSessionEndToEnd() throws {
        let track = try TrackParser.parse(data: Self.fixtureData(minutes: 4))
        let analysis = SessionSummarizer.analyze(track)
        #expect(analysis.capabilities.hasDoppler)      // the flag `certified` is built on
        #expect(analysis.capabilities.hasAccel)
        #expect(analysis.capabilities.hasHR)
        #expect(analysis.engineVersion == AnalysisEngine.version)
    }

    // MARK: - All the way into the library

    private func makeIngestor() throws -> (SessionIngestor, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("watch-ingest-\(UUID().uuidString)/Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (SessionIngestor(database: try AppDatabase.inMemory(),
                                archive: SessionArchive(root: root)), root)
    }

    /// **The test that matters, and the one whose absence hid a real bug.**
    ///
    /// Every file the app imports — a hand-picked one exactly as much as a GDPR ZIP — goes
    /// through `SessionIngestor.ingestContainer`, which asks `ZipWalker.classify` what the
    /// bytes are before anything else looks at them. A format missing from that ladder is not
    /// merely unclassified: it is dropped as `.ignored`, and the rider is told "no FIT found"
    /// about a file `WatchSessionParser` can read perfectly well. Parsing correctly is not
    /// the same as importing, and only this test knows the difference.
    @Test func aWatchContainerImportsThroughTheOrdinaryFileDoor() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let data = try Self.fixtureData(minutes: 4)

        let summary = await ingestor.ingestContainer(data: data, name: "session.cjw",
                                                     source: .appleWatch)
        #expect(summary.found == 1)
        #expect(summary.imported == 1)
        #expect(summary.failed.isEmpty)

        let sessions = try await ingestor.allSessions()
        #expect(sessions.count == 1)
        let row = try #require(sessions.first)
        #expect(row.sourceClass == "b")                 // certified
        #expect(row.importSource == "applewatch")
        #expect(row.discipline == "wingfoil")
        #expect(row.durationS > 0)
        #expect(row.startLat != nil && row.startLon != nil)

        // The archive keeps the container under its own extension and can re-parse it, which
        // is what makes this session survive the next engine bump.
        #expect(ingestor.archive.originalFormat(for: row.id) == .watch)
        #expect(try ingestor.archive.originalData(for: row.id) == data)
        let reanalysed = try await ingestor.reanalyze(row)
        #expect(reanalysed.capabilities.hasAccel)
        #expect(reanalysed.capabilities.hasDoppler)
    }

    @Test func classifyRecognisesAWatchContainer() throws {
        let data = try Self.fixtureData(minutes: 1)
        guard case .track(let payload) = ZipWalker.classify(data) else {
            Issue.record("a watch container must classify as a track, not as ignored")
            return
        }
        #expect(payload == data)
    }

    /// The same session sent twice — a re-queued transfer, or a phone that took delivery
    /// after the watch gave up waiting — must not appear twice.
    @Test func thePhoneDedupesARepeatedTransfer() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let data = try Self.fixtureData(minutes: 3)

        let first = await ingestor.ingestContainer(data: data, name: "a.cjw", source: .appleWatch)
        let second = await ingestor.ingestContainer(data: data, name: "a.cjw", source: .appleWatch)
        #expect(first.imported == 1)
        #expect(second.imported == 0)
        #expect(second.duplicates == 1)
        #expect(try await ingestor.allSessions().count == 1)
    }

    // MARK: - Provenance

    /// The Garmin BLE card is `watch` and an Apple Watch recording is `applewatch`. A
    /// substring test would conflate them, which is why `isNamed(in:)` splits.
    @Test func importSourcesMergeWithoutCollidingWithTheGarminCard() {
        #expect(ImportSource.appleWatch.rawValue == "applewatch")
        #expect(ImportSource.watch.rawValue == "watch")

        #expect(ImportSource.appleWatch.isNamed(in: "applewatch"))
        #expect(ImportSource.appleWatch.isNamed(in: "applewatch+icu"))
        #expect(!ImportSource.appleWatch.isNamed(in: "watch"))
        #expect(!ImportSource.watch.isNamed(in: "applewatch"))
        #expect(!ImportSource.appleWatch.isNamed(in: "file+icu"))
        #expect(!ImportSource.appleWatch.isNamed(in: nil))

        #expect(SessionIngestor.merge(sources: "icu", adding: .appleWatch) == "applewatch+icu")
        #expect(SessionIngestor.merge(sources: "applewatch", adding: .appleWatch) == "applewatch")
    }

    @Test func aWatchSessionPassesTheWatersportGate() throws {
        let track = try WatchSessionParser.parse(data: Self.fixtureData(minutes: 1))
        // `surfingSports` is not in the FIT sport allow-list; the discipline tag is what
        // gets a watch session through, exactly as our own developer fields do.
        #expect(SessionIngestor.isWatersport(track.capabilities))
    }
}
