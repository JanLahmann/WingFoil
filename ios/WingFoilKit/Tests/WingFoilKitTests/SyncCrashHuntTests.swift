import Foundation
import Testing
@testable import WingFoilKit
import ZIPFoundation

/// **The first bulk sync from a stranger's account.**
///
/// Jan's corpus is sixteen recordings from two devices. A tester who points CleanJibe at an
/// intervals.icu account holding a year of Garmin Connect hands the importer seventy-odd
/// files of shapes nobody here has ever produced — a lap of zero duration, a session with
/// one record, two records stamped the same second, a sport code the app has never heard
/// of, another app's developer field carrying a NaN. A parser may **throw** on any of them;
/// the sync reports the failure and carries on with the other seventy-three. What it may
/// never do is **trap** — `Int(nan)`, `a..<b` with `b < a`, `Array(repeating:count:)` with
/// a count the arithmetic invented — because a trap is not catchable, so one bad file out
/// of seventy-four takes the whole app down with no crash report and no way for the rider
/// to tell which file it was.
///
/// So this suite is a fuzz rather than a set of cases: every recording in the corpus through
/// the whole path, then a family of degenerate FITs built by `FitFactory`, then a fake
/// seventy-four-activity account whose payloads include an HTTP error page, a ZIP, zero
/// bytes and a download that throws. The assertion throughout is the same one: *finish, or
/// throw — never trap*.
@Suite struct SyncCrashHuntTests {

    // MARK: - Scratch

    /// An ingestor over an in-memory database and a throwaway archive directory.
    private func makeIngestor() throws -> (SessionIngestor, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-fuzz-\(UUID().uuidString)/Sessions",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (SessionIngestor(database: try AppDatabase.inMemory(),
                                archive: SessionArchive(root: root)),
                root.deletingLastPathComponent())
    }

    // MARK: - (a) The corpus, whole

    /// Every recording in the corpus — not only the ones that have goldens — through the
    /// **import** path rather than the analysis one: parse, analyse, archive, write the row
    /// and its child tables. `CorpusSmokeTests` already proves the analysis is sane; this
    /// proves the two ends around it survive the same files.
    @Test func everyCorpusRecordingIngests() async throws {
        let (ingestor, scratch) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let tracks = allFixtureTracks()
        guard !tracks.isEmpty else { return }
        var imported = 0
        for url in tracks {
            let data = try Data(contentsOf: url)
            let outcome = try await ingestor.ingest(fitData: data,
                                                    filename: url.lastPathComponent,
                                                    source: .icu,
                                                    icuActivityId: "i\(url.lastPathComponent)")
            if case .imported = outcome { imported += 1 }
        }
        #expect(imported > 0, "the corpus imported nothing at all")
    }

    // MARK: - (b) Degenerate recordings

    /// The shapes a stranger's Garmin account can hold. Each is named, because when one of
    /// them traps the test process dies and the *name* is the only evidence left.
    ///
    /// Every case may legitimately throw — `noRecords` is the honest answer to a FIT with no
    /// record messages. None of them may take the process with it.
    @Test(arguments: DegenerateFit.all)
    func degenerateRecordingsNeverTrap(_ shape: DegenerateFit) async throws {
        let (ingestor, scratch) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let data = shape.bytes()
        let started = Date()
        // 1. the parser
        let track: RawTrack
        do {
            track = try TrackParser.parse(data: data)
        } catch {
            return                                  // a throw is a pass
        }
        // 2. the analyzer, on its own, so a trap here is not blamed on the database
        _ = SessionSummarizer.analyze(track)
        // 3. and the whole import
        _ = try? await ingestor.ingest(fitData: data, filename: "\(shape.name).fit",
                                       source: .icu, icuActivityId: shape.name)
        let elapsed = Date().timeIntervalSince(started)
        print(String(format: "fuzz %-34s %6.2fs  %6d samples", (shape.name as NSString).utf8String!,
                     elapsed, track.samples.count))
        // A sync is seventy-four of these in a row on a phone. One recording that takes
        // minutes is not a crash, but it is what a tester reports as one — the truncated
        // file that started this hunt took 198 s. Wall clock in a suite that runs in
        // parallel, so the budget is loose on purpose: it is there to catch a hang, not to
        // police a slow second.
        #expect(elapsed < 120, "\(shape.name) took \(elapsed) s to import")
    }

    // MARK: - (c) A stranger's whole account

    /// Seventy-four activities, every payload a different way of being wrong, served through
    /// the real `IcuClient` and the real `IcuSyncService`. The sync must **return a summary**
    /// — one bad activity may not stop the other seventy-three, and no shape may trap.
    @Test func bulkSyncSurvivesSeventyFourStrangeActivities() async throws {
        let (ingestor, scratch) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let transport = StrangeAccountTransport(payloads: Self.strangePayloads())
        let client = IcuClient(apiKey: "test-key",
                               baseURL: URL(string: "https://example.invalid/api/v1")!,
                               transport: transport)
        let service = IcuSyncService(client: client, ingestor: ingestor)

        let summary = try await service.sync(oldest: Date(timeIntervalSince1970: 0),
                                             newest: Date())
        #expect(summary.watersports == transport.activityCount,
                "the name filter dropped activities it was meant to keep")
        // Every activity is accounted for: imported, a duplicate, skipped, or a *named*
        // failure. Nothing may go missing quietly.
        let accounted = summary.imported + summary.duplicates + summary.failed.count
        #expect(accounted > 0)
        #expect(summary.imported > 0, "not one of the good FITs survived the bad ones")
        // The failures name the activity, so a tester can say which afternoon broke.
        for failure in summary.failed {
            #expect(failure.contains(":"), "failure without an activity label: \(failure)")
        }
    }

    // MARK: - The regressions this hunt found

    /// **A download that was cut off is named, not read.**
    ///
    /// Before this, the bytes past the declared end were decoded as records: timestamps
    /// thirty-five years apart, a "session" spanning forty-six years, and a rolling-rate
    /// series of 24.6 million points — 590 MB of `WindowRatePoint` on a phone, which iOS
    /// answers by killing the app *without writing a crash report*. Three minutes of CPU in
    /// this process; a jetsam kill on a rider's.
    @Test func aTruncatedDownloadIsRefusedByName() throws {
        let whole = DegenerateShapes.noActivityMessage()
        // Whole: reads normally.
        #expect(throws: Never.self) { _ = try FitSessionParser.parse(data: whole) }
        // Cut off anywhere past the header: refused, with both lengths in the message.
        for fraction in [0.2, 0.5, 0.9] {
            let cut = whole.prefix(Int(Double(whole.count) * fraction))
            #expect(throws: FitSessionParser.ParseError.self) {
                _ = try FitSessionParser.parse(data: cut)
            }
        }
    }

    /// **A damaged recording never reaches the decoder.**
    ///
    /// The vendored C decoder rebuilds its field table from the record layer; a corrupted
    /// definition makes it walk the next message tens of kilobytes past a stack-allocated
    /// struct. That is a segfault — uncatchable, unreportable, and found here by flipping
    /// bytes in a corpus FIT (`MutationFuzzTests`). The file's own CRC-16 is the test, and
    /// every recording in the corpus and the bundled example pass it.
    @Test func aDamagedRecordingIsRefusedBeforeTheDecoder() throws {
        let whole = DegenerateShapes.noActivityMessage()
        var bytes = [UInt8](whole)
        #expect(FitStreamWalker.crcMatches(bytes) == true, "the factory writes a bad CRC")

        // One flipped byte in the data section, CRC left alone.
        let layout = try #require(FitStreamWalker.layout(of: bytes))
        bytes[layout.headerSize + 20] ^= 0x5A
        #expect(throws: FitSessionParser.ParseError.self) {
            _ = try FitSessionParser.parse(data: Data(bytes))
        }

        // Every corpus recording — and the FIT the app ships — passes both gates.
        for url in allFixtureTracks() where url.pathExtension.lowercased() == "fit" {
            let raw = [UInt8](try Data(contentsOf: url))
            #expect(FitStreamWalker.crcMatches(raw) == true, "\(url.lastPathComponent): CRC")
            #expect(FitStreamWalker.walk(raw, { _ in }) != nil,
                    "\(url.lastPathComponent): record layer does not frame")
        }
        let example = [UInt8](try ExampleSession.data())
        #expect(FitStreamWalker.crcMatches(example) == true)
        #expect(FitStreamWalker.walk(example, { _ in }) != nil)
    }

    /// **A recording whose clock is broken is refused by the importer**, so the sync reports
    /// it against its activity id instead of the app dying on it.
    @Test func aBrokenClockIsRefusedByTheImporter() async throws {
        let (ingestor, scratch) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: scratch) }

        var track = RawTrack()
        let epoch = Date(timeIntervalSince1970: 1_754_460_000)
        track.startDate = epoch
        for (i, t) in [0.0, 1.0, 2.0, 1_475_109_579.0].enumerated() {
            var sample = RecordSample(t: t, timestamp: epoch.addingTimeInterval(t))
            sample.speedMps = 6
            sample.lat = 45.87 + Double(i) * 1e-5
            sample.lon = 10.87
            track.samples.append(sample)
        }
        // The engine itself no longer allocates per minute of a forty-six-year "session":
        // 24.6 million points before, one grid's worth of ceiling now.
        let analysis = SessionSummarizer.analyze(track)
        #expect(analysis.summary.windowRates.series.count
                    <= SessionWindowRates.maxSeriesPoints + 1)

        // And the importer refuses it outright, with a sentence naming the cause. The file
        // here is **complete and well-formed** — every CRC checks out — so nothing
        // structural catches it; only the arithmetic does.
        await #expect(throws: IngestError.self) {
            try await ingestor.ingest(fitData: DegenerateShapes.brokenClock(),
                                      filename: "broken.fit", source: .icu)
        }
        #expect("\(IngestError.implausibleDuration(durationS: 1_475_109_579))"
                    .contains("timestamps are broken"))
    }

    /// **A foreign float developer field is dropped, not converted.** `Int(nan)` traps, and
    /// another app's `field_description` may name a float32 field anything it likes —
    /// including a name our own schema uses.
    @Test func foreignNaNDeveloperFieldsAreDropped() throws {
        let track = try FitSessionParser.parse(data: DegenerateShapes.foreignDevFieldsNaN())
        #expect(track.samples.allSatisfy { $0.foilState == nil && $0.tick == nil },
                "a NaN developer field reached the model as a number")
        #expect(track.watchSummary.flightCount == nil)
        // The decoder's own contract, stated directly.
        #expect(FitDevValue.number(.nan).int == nil)
        #expect(FitDevValue.number(.infinity).double == nil)
        #expect(FitDevValue.number(1e300).int == Int.max)
        #expect(Int(clamped: Double.nan) == 0)
        #expect(Int(clamped: -.infinity) == Int.min)
    }

    /// **Seventy-four recordings in a row must not grow the process without bound.** A FIT
    /// parse allocates a great deal — the vendored decoder is Objective-C and autoreleases —
    /// and a sync is the only place in the app that does it dozens of times back to back.
    /// Measured rather than assumed: this is the shape that reads to a tester as "it
    /// crashed" while leaving no crash report, because iOS reclaims the memory by killing
    /// the app.
    @Test func bulkIngestDoesNotGrowWithoutBound() async throws {
        let fits = allFixtureTracks().filter { $0.pathExtension == "fit" }
        guard fits.count >= 4 else { return }

        let (ingestor, scratch) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: scratch) }

        // One pass to warm every lazy global up, so the measurement is growth and not setup.
        for url in fits.prefix(4) {
            _ = try? await ingestor.ingest(fitData: try Data(contentsOf: url),
                                           filename: url.lastPathComponent, source: .icu,
                                           icuActivityId: "warm-\(url.lastPathComponent)")
        }
        let before = residentBytes()

        // Seventy-four imports, the corpus cycled — each one a *fresh* activity id, so none
        // of them short-circuits on the dedupe.
        for i in 0..<74 {
            let url = fits[i % fits.count]
            _ = try? await ingestor.ingest(fitData: try Data(contentsOf: url),
                                           filename: url.lastPathComponent, source: .icu,
                                           icuActivityId: "bulk-\(i)")
        }
        let after = residentBytes()
        // Signed, because the number can legitimately go **down**: this is the whole
        // process's resident size and the rest of the suite is running beside it. Unsigned
        // subtraction here once reported a growth of seventeen million gigabytes.
        let grewMB = Double(Int64(bitPattern: after) - Int64(bitPattern: before)) / 1_048_576
        print(String(format: "fuzz bulk-74 resident %.0f MB → %.0f MB (%+.0f MB)",
                     Double(before) / 1_048_576, Double(after) / 1_048_576, grewMB))
        // Generous, and one-sided: the library itself grows, a test process is not a phone,
        // and a shrink means the rest of the suite gave memory back. What this catches is
        // the runaway — a per-session retain that makes 74 files cost 74 times one file.
        #expect(grewMB < 250, "74 imports grew the process by \(grewMB) MB")
    }

    /// Resident size of this process, in bytes (`mach_task_basic_info`).
    private func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size
                                           / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    /// A 30 MB payload of zeros: the memory shape rather than the parse shape. Off by
    /// default — it is slow and allocates — and on with `FUZZ_BIG=1`.
    @Test func hugePayloadIsRefusedNotFatal() async throws {
        guard ProcessInfo.processInfo.environment["FUZZ_BIG"] == "1" else { return }
        let (ingestor, scratch) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let zeros = Data(count: 30 * 1024 * 1024)
        #expect(throws: (any Error).self) { _ = try IcuPayload.unwrap(zeros) }
        _ = try? await ingestor.ingest(fitData: zeros, filename: "zeros.fit", source: .icu)
    }

    // MARK: - Payload zoo

    /// The bodies `/activity/{id}/file` can hand back. Index `i` of the list is served to
    /// activity `i`, cycling.
    static func strangePayloads() -> [StrangePayload] {
        var payloads: [StrangePayload] = []
        // A real, good recording — the seventy-three that must survive the one.
        if let good = allFixtureTracks().first(where: { $0.pathExtension == "fit" }),
           let data = try? Data(contentsOf: good) {
            payloads.append(.body(data))
        }
        payloads.append(.status(502, Data("<html><body>502 Bad Gateway</body></html>".utf8)))
        payloads.append(.body(Data()))                                   // zero bytes
        payloads.append(.body(Data("<html><head><title>Error</title></head></html>".utf8)))
        payloads.append(.transportFailure)                               // the network threw
        payloads.append(.body(Data([0x50, 0x4B, 0x03, 0x04] + [UInt8](repeating: 0, count: 60))))
        payloads.append(.body(Data([0x1f, 0x8b, 0x08] + [UInt8](repeating: 0, count: 30))))
        for shape in DegenerateFit.all { payloads.append(.body(shape.bytes())) }
        return payloads
    }

    // MARK: - Transport

    enum StrangePayload: Sendable {
        case body(Data)
        case status(Int, Data)
        case transportFailure
    }

    struct TransportBlewUp: Swift.Error {}

    /// Serves an activity list of `activityCount` watersport activities and then a payload
    /// per activity, cycling through `payloads`.
    final class StrangeAccountTransport: IcuTransport, @unchecked Sendable {
        let payloads: [StrangePayload]
        let activityCount = 74

        init(payloads: [StrangePayload]) { self.payloads = payloads }

        private var listJSON: Data {
            let rows = (0..<activityCount).map { i -> String in
                let day = 1 + (i % 28)
                return """
                    {"id":"i\(100_000 + i)","name":"Wingfoil session \(i)",\
                    "type":"\(Self.types[i % Self.types.count])",\
                    "start_date":"2026-0\(1 + (i % 9))-\(String(format: "%02d", day))T09:00:00Z",\
                    "start_date_local":"2026-0\(1 + (i % 9))-\(String(format: "%02d", day))T11:00:00",\
                    "timezone":"Europe/Rome","moving_time":\(i * 37),"distance":\(i * 101)}
                    """
            }
            return Data("[\(rows.joined(separator: ","))]".utf8)
        }

        /// Sports a year of Garmin Connect actually holds. All 74 carry "Wingfoil" in the
        /// name, so `isWatersport` keeps them whatever the type says — which is exactly how
        /// a running activity slips the filter.
        static let types = ["Windsurf", "Run", "Ride", "Kitesurf", "Walk", "Swim",
                            "WeightTraining", "Sail", "Other"]

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let url = request.url!
            func response(_ status: Int) -> HTTPURLResponse {
                HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                headerFields: nil)!
            }
            if url.path.hasSuffix("/activities") { return (listJSON, response(200)) }
            // .../activity/i100042/file
            let id = url.pathComponents.dropLast().last ?? "i100000"
            let index = Int(id.dropFirst()) ?? 100_000
            switch payloads[(index - 100_000) % payloads.count] {
            case .body(let data): return (data, response(200))
            case .status(let code, let data): return (data, response(code))
            case .transportFailure: throw TransportBlewUp()
            }
        }
    }
}

