import Foundation
import Testing
@testable import WingFoilKit

/// **Stream 1 of the direct transfer** — `wrist.v1` (docs/transfer-format.md §2b, ADR-031):
/// the 25 Hz wrist magnitudes, inside the windows the watch flagged, arriving minutes after
/// the recording they belong to.
///
/// The worked example of §2b is the pin, the same way §2.3's is for stream 0: three
/// implementations encode these bytes — the watch in Monkey C, `lab/tools/cjr_ref.py` in
/// Python and `DirectWristEncoder` here — and the only thing that keeps them in step is that
/// all three are held against one hex string, copied out of the document character for
/// character.
@Suite struct DirectWristTests {

    // MARK: - The worked example (docs/transfer-format.md §2b)

    static let header = DirectStreamHeader(stream: DirectWrist.wristStream,
                                           appVersion: 9 * 256 + 2,
                                           startEpochS: 1_756_556_820,
                                           windDirDeg: 200, utcOffsetS: 7200)

    /// One window of five samples opening 1.4 s into the session: a resting wrist, two small
    /// steps, a landing spike no 8-bit delta can say, and a step back down.
    static let window = DirectWristWindow(startEpochMs: 1_756_556_821_400,
                                          magnitudes: [100, 103, 99, 400, 398])

    static let exampleHex =
        "434a5231" + "02" + "01" + "0209" + "14eeb268" + "c800" + "00" + "00" + "7800" + "0000"
        + "ff" + "15eeb268" + "9001" + "0500"
        + "fe" + "6400" + "81" + "7a" + "fe" + "9001" + "7c"

    static func exampleBytes() -> Data {
        var encoder = DirectWristEncoder(header: header)
        encoder.push(window)
        return encoder.archive()
    }

    @Test func theWorkedExampleEncodesToThePinnedHex() {
        let bytes = Self.exampleBytes()
        #expect(bytes.count == 38)
        #expect(DirectStreamTests.hex(bytes) == Self.exampleHex)
    }

    /// The committed fixture is the same 38 bytes — a file a decoder in any language can be
    /// pointed at without reading a hex string out of a document first.
    @Test func theCommittedFixtureIsTheWorkedExample() throws {
        let url = testFixturesDir.appendingPathComponent("direct/example-wrist.cjr")
        let data = try Data(contentsOf: url)
        #expect(DirectStreamTests.hex(data) == Self.exampleHex)
        let (_, windows) = try DirectWristDecoder.decode(data)
        #expect(windows == [Self.window])
    }

    @Test func theWorkedExampleDecodesBack() throws {
        let (header, windows) = try DirectWristDecoder.decode(Self.exampleBytes())
        #expect(header.stream == DirectWrist.wristStream)
        #expect(header.startEpochS == 1_756_556_820)
        #expect(header.utcOffsetS == 7200)
        #expect(windows == [Self.window])
    }

    /// Page 0 is the twenty-byte header on its own — the watch drops stream-1 pages under
    /// budget pressure and only numbers them at save, so the header cannot ride on a page
    /// that might not survive.
    @Test func pageZeroIsTheHeaderAlone() {
        var encoder = DirectWristEncoder(header: Self.header)
        encoder.push(Self.window)
        let pages = encoder.close()
        #expect(pages.count == 2)
        #expect(pages[0].count == DirectStream.headerBytes)
        #expect(pages[1][pages[1].startIndex] == DirectWrist.windowTag)
    }

    @Test func everyPageOpensWithAWindowAndDecodesOnItsOwn() throws {
        var encoder = DirectWristEncoder(header: Self.header)
        let windows = Self.manyWindows(count: 200)
        for window in windows { encoder.push(window) }
        let pages = encoder.close()
        #expect(pages.count > 2)
        for page in pages.dropFirst() {
            #expect(page.count <= DirectStream.pageBytes)
            #expect(page[page.startIndex] == DirectWrist.windowTag)
            // Page 0's header in front of it, and the page reads on its own.
            let (_, decoded) = try DirectWristDecoder.decode(pages[0] + page)
            #expect(!decoded.isEmpty)
        }
        let (_, back) = try DirectWristDecoder.decode(pages.reduce(Data(), +))
        #expect(back == windows)
    }

    /// A step past ±127 centi-g escapes to two bytes; everything inside it is one.
    @Test func aStepTheDeltaCannotSayEscapes() throws {
        let window = DirectWristWindow(startEpochMs: 1_000_000,
                                       magnitudes: [100, 100 + DirectWrist.deltaMax, 0, 65535])
        let body = DirectWristEncoder.encode(window)
        #expect(body.count == DirectWrist.windowHeaderBytes + 3 + 1 + 3 + 3)
        let (_, back) = try DirectWristDecoder.decode(
            DirectStreamEncoder.pack(Self.header) + body)
        #expect(back == [window])
    }

    @Test func aMagnitudeIsClampedRatherThanWrapped() throws {
        let window = DirectWristWindow(startEpochMs: 0, magnitudes: [-5, 70000])
        let (_, back) = try DirectWristDecoder.decode(
            DirectStreamEncoder.pack(Self.header) + DirectWristEncoder.encode(window))
        #expect(back == [DirectWristWindow(startEpochMs: 0, magnitudes: [0, 65535])])
    }

    /// The parser's rule everywhere: a structurally broken stream throws, a trailing window
    /// short of its own width is dropped. Never a trap, whatever the bytes are.
    @Test func aTornStreamIsRefusedOrTruncatedButNeverTraps() throws {
        var encoder = DirectWristEncoder(header: Self.header)
        for window in Self.manyWindows(count: 4) { encoder.push(window) }
        let whole = encoder.archive()
        for cut in DirectStream.headerBytes...whole.count {
            _ = try? DirectWristDecoder.decode(whole.prefix(cut))
        }
        // A record stream handed to the wrist decoder is refused, not read sideways.
        #expect(throws: DirectStreamError.self) {
            try DirectWristDecoder.decode(DirectStreamTests.exampleBytes())
        }
    }

    @Test func randomBytesNeverTrapTheDecoder() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            var data = DirectStreamEncoder.pack(Self.header)
            data.append(DirectWrist.windowTag)
            for _ in 0..<Int.random(in: 1...400, using: &rng) {
                data.append(UInt8.random(in: 0...255, using: &rng))
            }
            _ = try? DirectWristDecoder.decode(data)
        }
    }

    // MARK: - Onto the track

    @Test func windowsBecomeAccelSamplesOnTheRecordClock() throws {
        let (header, records) = DirectStreamTests.syntheticSession()
        var stream = DirectStreamEncoder(header: header)
        for record in records { stream.push(record) }
        let recordBytes = stream.archive()

        // Two windows, one of them inside the session's first minute.
        let base = header.startEpochS
        let windows = [
            DirectWristWindow(startEpochMs: (base + 30) * 1000,
                              magnitudes: Self.pumping(count: 250)),
            DirectWristWindow(startEpochMs: (base + 120) * 1000 + 400,
                              magnitudes: Self.pumping(count: 250)),
        ]
        var wrist = DirectWristEncoder(header: header)
        for window in windows { wrist.push(window) }

        let track = try DirectStreamParser.parse(data: recordBytes, wrist: wrist.archive())
        #expect(track.accel.count == 500)
        // The first sample sits thirty seconds into the session, on the records' own zero.
        #expect(abs(track.accel[0].t - 30) < 0.001)
        #expect(abs(track.accel[250].t - 120.4) < 0.001)
        // 40 ms apart inside a window, and time-sorted across them.
        #expect(abs(track.accel[1].t - track.accel[0].t - 0.04) < 1e-9)
        #expect(track.accel == track.accel.sorted { $0.t < $1.t })
        // Centi-g on the wire, g on the track: a resting wrist reads about one.
        #expect(track.accel.contains { abs($0.magnitudeG - 1.0) < 0.5 })
    }

    /// **The capability, and the letter that does not move.** `sourceClass` is `a` on the
    /// developer fields with or without a wrist stream; what the stream changes is that the
    /// engine gets a `PumpTrack` where it got nil.
    @Test func theWristStreamTurnsOnTheAccelCapabilityAndNotTheClass() throws {
        let (header, records) = DirectStreamTests.syntheticSession()
        var stream = DirectStreamEncoder(header: header)
        for record in records { stream.push(record) }
        let recordBytes = stream.archive()

        let without = try DirectStreamParser.parse(data: recordBytes)
        #expect(!without.capabilities.hasAccel)
        #expect(without.capabilities.sourceClass == "a")
        #expect(PumpAnalyzer.track(without, config: PumpConfig()) == nil)

        var wrist = DirectWristEncoder(header: header)
        for window in Self.manyWindows(count: 40, from: header.startEpochS) {
            wrist.push(window)
        }
        let with = try DirectStreamParser.parse(data: recordBytes, wrist: wrist.archive())
        #expect(with.capabilities.hasAccel)
        #expect(with.capabilities.accelClockReconstructed == false)
        #expect(with.capabilities.sourceClass == "a")      // unchanged, and meant to be
        #expect(PumpAnalyzer.track(with, config: PumpConfig()) != nil)
    }

    /// The seconds between two windows are a **sensor gap**, which is what the pump grid has
    /// always called a stretch it has no samples for: `valid` false there, and no stroke
    /// picked. That is the whole reason a windowed stream needs no new concept.
    @Test func theSecondsBetweenWindowsAreAnOrdinarySensorGap() throws {
        let base = 1_756_556_820
        let header = DirectStreamHeader(appVersion: 9 * 256 + 2, startEpochS: base,
                                        windDirDeg: 200)
        let times = Self.manyWindows(count: 3, from: base, everyS: 60)
        var samples: [AccelSample] = []
        for window in times {
            var t = Double(window.startEpochMs) / 1000 - Double(base)
            for magnitude in window.magnitudes {
                samples.append(AccelSample(t: t, magnitudeG: DirectWrist.gravities(magnitude)))
                t += Double(DirectWrist.stepMs) / 1000
            }
        }
        var track = RawTrack()
        track.accel = samples
        let pump = try #require(PumpAnalyzer.track(track, config: PumpConfig()))
        // Covered where a window is, not covered between them.
        let covered = zip(pump.t, pump.valid).filter { $0.1 }.map(\.0)
        #expect(covered.contains { abs($0 - 0) < 1 })
        #expect(!covered.contains { $0 > 20 && $0 < 55 })
        // And no stroke is reported out of an uncovered stretch.
        #expect(pump.strokes(from: 20, to: 55).isEmpty)
        _ = header
    }

    // MARK: - The archive and the re-derive

    @Test func theSidecarRidesBesideTheOriginalAndReanalysisSeesIt() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-wrist-\(UUID().uuidString)/Sessions",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let ingestor = SessionIngestor(database: try AppDatabase.inMemory(),
                                       archive: SessionArchive(root: root))

        let (header, records) = DirectStreamTests.syntheticSession()
        var stream = DirectStreamEncoder(header: header)
        for record in records { stream.push(record) }
        guard case .imported(let row) = try await ingestor.ingest(
            fitData: stream.archive(), filename: "session.cjr", source: .watchDirect) else {
            Issue.record("expected the stream to import")
            return
        }
        #expect(row.sourceClass == "a")
        #expect(row.hasAccel == false)

        var wrist = DirectWristEncoder(header: header)
        for window in Self.manyWindows(count: 60, from: header.startEpochS) {
            wrist.push(window)
        }
        let analysis = try await ingestor.attachWristStream(wrist.archive(), to: row)
        #expect(analysis != nil)
        #expect(analysis?.capabilities.hasAccel == true)

        // The sidecar is on disk beside the original, and `rawTrack` attaches it — which is
        // what makes every later re-analysis see it too, with no second ingest path.
        #expect(FileManager.default.fileExists(
            atPath: ingestor.archive.wristURL(for: row.id).path))
        #expect(ingestor.archive.originalFormat(for: row.id) == .direct)
        let track = try ingestor.archive.rawTrack(for: row.id)
        #expect(track.capabilities.hasAccel)
        #expect(!track.accel.isEmpty)

        let stored = try #require(try await ingestor.allSessions().first)
        #expect(stored.id == row.id)                      // the same row, not a second one
        #expect(stored.hasAccel == true)
        #expect(stored.sourceClass == "a")                // and the same letter
        #expect(try await ingestor.allSessions().count == 1)
    }

    /// A wrist stream has nothing to attach to a session that did not come over the link —
    /// a GPX or a FIT carries its own accelerometer channel or none at all. And a sidecar
    /// that cannot be decoded is refused rather than filed: one that was filed would be
    /// re-read and re-refused at every re-analysis for ever.
    @Test func aWristStreamIsRefusedWhereItHasNothingToAttachTo() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-wrist-\(UUID().uuidString)/Sessions",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let ingestor = SessionIngestor(database: try AppDatabase.inMemory(),
                                       archive: SessionArchive(root: root))
        var wrist = DirectWristEncoder(header: Self.header)
        wrist.push(Self.window)
        let sidecar = wrist.archive()

        // A GPX session: not a direct stream, so there is no second channel to attach.
        guard case .imported(let gpxRow) = try await ingestor.ingest(
            fitData: Self.gpx(), filename: "ride.gpx", source: .file) else {
            Issue.record("expected the GPX to import")
            return
        }
        #expect(try await ingestor.attachWristStream(sidecar, to: gpxRow) == nil)
        #expect(!FileManager.default.fileExists(
            atPath: ingestor.archive.wristURL(for: gpxRow.id).path))

        // A direct session with bytes that are not a wrist stream: also refused.
        let (header, records) = DirectStreamTests.syntheticSession()
        var stream = DirectStreamEncoder(header: header)
        for record in records { stream.push(record) }
        guard case .imported(let directRow) = try await ingestor.ingest(
            fitData: stream.archive(), filename: "session.cjr", source: .watchDirect) else {
            Issue.record("expected the stream to import")
            return
        }
        #expect(try await ingestor.attachWristStream(Data([0, 1, 2, 3]), to: directRow) == nil)
        #expect(try await ingestor.attachWristStream(
            DirectStreamEncoder.pack(Self.header), to: directRow) == nil)   // header only
        #expect(!FileManager.default.fileExists(
            atPath: ingestor.archive.wristURL(for: directRow.id).path))
    }

    @Test func theSessionAWristStreamBelongsToIsFoundByItsStart() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-wrist-\(UUID().uuidString)/Sessions",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let ingestor = SessionIngestor(database: try AppDatabase.inMemory(),
                                       archive: SessionArchive(root: root))
        let (header, records) = DirectStreamTests.syntheticSession()
        var stream = DirectStreamEncoder(header: header)
        for record in records { stream.push(record) }
        _ = try await ingestor.ingest(fitData: stream.archive(), filename: "session.cjr",
                                      source: .watchDirect)
        let start = Date(timeIntervalSince1970: Double(header.startEpochS))
        #expect(try await ingestor.session(nearStart: start) != nil)
        #expect(try await ingestor.session(nearStart: start.addingTimeInterval(30)) != nil)
        #expect(try await ingestor.session(nearStart: start.addingTimeInterval(600)) == nil)
    }

    // MARK: - Fixtures

    /// A plausible pump: a ~1 Hz swing of about ±0.4 g around a resting 1 g, in centi-g.
    static func pumping(count: Int) -> [Int] {
        (0..<count).map { i in
            Int((100 + 40 * sin(Double(i) * 2 * .pi / 25)).rounded())
        }
    }

    /// A minute of GPX, for the one test that needs a session the link did not bring.
    static func gpx() -> Data {
        var body = "<trk><trkseg>"
        for i in 0..<120 {
            let time = Date(timeIntervalSince1970: 1_756_600_000 + Double(i))
                .formatted(.iso8601)
            body += "<trkpt lat=\"\(45.8722 + Double(i) * 0.0001)\" lon=\"10.8747\">"
                + "<ele>60</ele><time>\(time)</time></trkpt>"
        }
        return Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
            \(body)</trkseg></trk></gpx>
            """.utf8)
    }

    static func manyWindows(count: Int, from base: Int = 1_756_556_820,
                            everyS: Int = 30) -> [DirectWristWindow] {
        (0..<count).map { i in
            DirectWristWindow(startEpochMs: (base + i * everyS) * 1000,
                              magnitudes: pumping(count: DirectWrist.windowMaxSamples))
        }
    }
}
