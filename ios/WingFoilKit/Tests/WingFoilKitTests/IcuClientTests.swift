import Foundation
import Testing
@testable import WingFoilKit
import ZIPFoundation

/// The `/file` endpoint hands back whatever wrapper intervals.icu kept, so the unwrap
/// path is the one piece of the sync that must never guess wrong. Tiny synthetic
/// payloads only — no network, no fixtures.
@Suite struct IcuPayloadTests {

    /// Smallest byte string that satisfies our FIT sniff: 12-byte header with `.FIT`
    /// at 8..<12, plus a little body so it looks like a file.
    private func fakeFit(marker: UInt8 = 0x2a) -> Data {
        var data = Data([12, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        data.append(contentsOf: Array(".FIT".utf8))
        data.append(contentsOf: [UInt8](repeating: marker, count: 64))
        return data
    }

    private func zip(entries: [(String, Data)]) throws -> Data {
        let archive = try Archive(data: Data(), accessMode: .create, pathEncoding: nil)
        for (name, payload) in entries {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .deflate) { position, size in
                payload.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        return archive.data ?? Data()
    }

    @Test func detectsPlainFit() throws {
        let fit = fakeFit()
        #expect(IcuPayload.isFit(fit))
        #expect(!IcuPayload.isGzip(fit))
        #expect(!IcuPayload.isZip(fit))
        #expect(try IcuPayload.unwrap(fit) == fit)
    }

    @Test func unwrapsGzippedFit() throws {
        let fit = fakeFit(marker: 0x5b)
        let gz = try Gzip.compress(fit)
        #expect(IcuPayload.isGzip(gz))
        #expect(!IcuPayload.isFit(gz))
        #expect(try IcuPayload.unwrap(gz) == fit)
    }

    @Test func unwrapsZippedFit() throws {
        let fit = fakeFit(marker: 0x7e)
        let payload = try zip(entries: [("activity.json", Data("{}".utf8)),
                                        ("12345_ACTIVITY.fit", fit)])
        #expect(IcuPayload.isZip(payload))
        #expect(try IcuPayload.unwrap(payload) == fit)
    }

    @Test func unwrapsGzippedZip() throws {
        let fit = fakeFit(marker: 0x11)
        let gz = try Gzip.compress(try zip(entries: [("a.fit", fit)]))
        #expect(try IcuPayload.unwrap(gz) == fit)
    }

    @Test func rejectsNonFitPayloads() throws {
        #expect(throws: IcuPayload.Error.self) { try IcuPayload.unwrap(Data()) }
        #expect(throws: IcuPayload.Error.self) {
            try IcuPayload.unwrap(Data("<html>404 not found</html>".utf8))
        }
        #expect(throws: IcuPayload.Error.self) {
            try IcuPayload.unwrap(try zip(entries: [("readme.txt", Data("hi".utf8))]))
        }
    }

    @Test func gzipRoundTripsLargePayloads() throws {
        // Multi-buffer output exercises the streaming inflate loop (64 KiB chunks).
        var big = Data()
        for i in 0..<200_000 { big.append(UInt8(i % 251)) }
        #expect(try Gzip.decompress(try Gzip.compress(big)) == big)
    }

    @Test func walksNestedZipsLikeTheGdprExport() throws {
        // Garmin's export: ZIP of ZIPs of FITs, mixed with JSON noise.
        let inner1 = try zip(entries: [("2026-08-01.fit", fakeFit(marker: 1)),
                                       ("summary.json", Data("{}".utf8))])
        let inner2 = try zip(entries: [("2026-08-02.fit.gz", try Gzip.compress(fakeFit(marker: 2)))])
        let outer = try zip(entries: [("part1.zip", inner1), ("part2.zip", inner2),
                                      ("profile.json", Data("{}".utf8))])

        let result = ZipWalker.walk(data: outer, name: "export.zip")
        #expect(result.fits.count == 2)
        #expect(result.archives == 3)
        #expect(result.ignoredEntries == 2)                       // the two JSON files
        #expect(result.fits.allSatisfy { IcuPayload.isFit($0.data) })
        #expect(result.fits.contains { $0.name.hasSuffix("part1.zip/2026-08-01.fit") })
    }

    @Test func walkerPassesThroughASingleFit() {
        let result = ZipWalker.walk(data: fakeFit(), name: "session.fit")
        #expect(result.fits.count == 1)
        #expect(result.archives == 0)
        #expect(result.fits.first?.name == "session.fit")
    }
}

@Suite struct IcuClientTests {

    /// Records the request it was handed and replays a canned response.
    private final class Recorder: @unchecked Sendable {
        var request: URLRequest?
    }

    private struct StubTransport: IcuTransport {
        let recorder: Recorder
        let status: Int
        let body: Data

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            recorder.request = request
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: nil)!
            return (body, response)
        }
    }

    @Test func usesPersonalKeyBasicAuth() {
        // intervals.icu personal keys authenticate as user "API_KEY".
        #expect(IcuClient.basicAuth(key: "abc123")
                == "Basic " + Data("API_KEY:abc123".utf8).base64EncodedString())
    }

    @Test func decodesActivityListAndFiltersWatersports() async throws {
        let json = """
        [{"id":"i111","name":"Nago-Torbole Windsurfen","type":"Windsurf",
          "start_date_local":"2026-08-06T13:59:01","moving_time":5400,"distance":24000.0},
         {"id":"i222","name":"Wingfoiling","type":"Walk","start_date_local":"2026-08-06T07:57:21"},
         {"id":"i333","name":"Morning Ride","type":"Ride","start_date_local":"2026-08-05T09:00:00"},
         {"id":444,"name":"FoilMotion","type":"Walk","start_date_local":"2026-08-05T13:56:00"}]
        """
        let recorder = Recorder()
        let client = IcuClient(apiKey: "k", transport: StubTransport(
            recorder: recorder, status: 200, body: Data(json.utf8)))

        let activities = try await client.activities(
            oldest: Date(timeIntervalSince1970: 1_750_000_000),
            newest: Date(timeIntervalSince1970: 1_785_000_000))
        #expect(activities.count == 4)
        #expect(activities[3].id == "444")                       // numeric ids survive
        #expect(activities[0].movingTimeS == 5400)

        let watersports = activities.filter(IcuClient.isWatersport)
        #expect(watersports.map(\.id) == ["i111", "i222", "444"])  // Walk rescued by name

        let request = try #require(recorder.request)
        let url = try #require(request.url?.absoluteString)
        #expect(url.contains("athlete/0/activities"))
        #expect(url.contains("oldest=") && url.contains("newest="))
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
    }

    @Test func buildsReadableArchiveFilenames() {
        let activity = IcuActivity(id: "i86544321", name: "Nago-Torbole Windsurfen")
        #expect(IcuSyncService.filename(for: activity)
                == "i86544321_nago-torbole-windsurfen_icu.fit")
        #expect(IcuSyncService.filename(for: IcuActivity(id: "i1", name: "  "))
                == "i1_session_icu.fit")
    }

    @Test func parsesLocalStartDate() {
        let activity = IcuActivity(id: "i1", startDateLocal: "2026-08-06T07:57:21")
        let date = activity.startDate
        #expect(date != nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        #expect(calendar.component(.hour, from: date!) == 7)
    }

    @Test func downloadsAndUnwrapsOriginalFit() async throws {
        var fit = Data([12, 0x10, 0, 0, 0, 0, 0, 0])
        fit.append(contentsOf: Array(".FIT".utf8))
        fit.append(contentsOf: [UInt8](repeating: 9, count: 32))
        let recorder = Recorder()
        let client = IcuClient(apiKey: "k", transport: StubTransport(
            recorder: recorder, status: 200, body: try Gzip.compress(fit)))

        #expect(try await client.originalFit(activityID: "i111") == fit)
        #expect(recorder.request?.url?.path.hasSuffix("/activity/i111/file") == true)
    }

    @Test func surfacesAuthFailures() async {
        let client = IcuClient(apiKey: "bad", transport: StubTransport(
            recorder: Recorder(), status: 401, body: Data()))
        await #expect(throws: IcuClient.Error.self) {
            _ = try await client.activities(oldest: Date())
        }
    }

    @Test func refusesToCallWithoutAKey() async {
        let client = IcuClient(apiKey: "", transport: StubTransport(
            recorder: Recorder(), status: 200, body: Data("[]".utf8)))
        await #expect(throws: IcuClient.Error.self) {
            _ = try await client.activities(oldest: Date())
        }
    }
}
