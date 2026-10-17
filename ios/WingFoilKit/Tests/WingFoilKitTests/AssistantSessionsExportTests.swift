import Foundation
import Testing
@testable import WingFoilKit

/// **Ask CleanJibe's session states, one per corpus session, for the eval set**
/// (`docs/copy/assistant/sessions/<short-id>.json`, read by `evals-sessions.jsonl`).
///
/// Each file is what the app would send with a question about that session: the beta,
/// 1.0.1, build 135, speed in knots — except two sessions in km/h, so the evals see a
/// rider who reads another unit. No tips: the app sends none (`AskState.session` passes
/// no `tips`), so the evals ask what the app's state carries.
///
/// ```sh
/// COPY_WRITE=1 swift test --filter AssistantSessionsExportTests
/// ```
///
/// The plain run checks every file is what the kit builds now, so an engine change that
/// moves a number fails here until the states (and any eval that quotes them) are redone.
@Suite struct AssistantSessionsExportTests {

    static let dir = AssistantStateTests.assistantDir.appendingPathComponent("sessions")

    /// The sessions read in km/h.
    static let kmh: Set<String> = ["0803-1440-native", "0829-1440-ciq"]

    /// `2026-08-03-1440_nago-torbole-windsurfen_native` → `0803-1440-native`; the three
    /// re-recordings of 30 Aug keep their format in the id.
    static func shortId(_ stem: String) -> String {
        let date = stem.prefix(15)                       // 2026-08-03-1440
        let base = date.dropFirst(5).replacingOccurrences(of: "-", with: "")
        let day = String(base.prefix(4)) + "-" + String(base.dropFirst(4))
        let tail: String
        if stem.hasSuffix("nago-torbole-nospeed") { tail = "tcx-nospeed" }
        else if stem.hasSuffix("nago-torbole-speed") { tail = "tcx-speed" }
        else if stem.hasSuffix("_nago-torbole") { tail = "gpx" }
        else { tail = String(stem.split(separator: "_").last ?? "") }
        return day + "-" + tail
    }

    static func stems() throws -> [String] {
        let goldens = testFixturesDir.appendingPathComponent("goldens")
        return try FileManager.default.contentsOfDirectory(atPath: goldens.path)
            .filter { $0.hasSuffix(".expected.json") && $0.hasPrefix("20") }
            .map { String($0.dropLast(".expected.json".count)) }
            .sorted()
    }

    /// One session's state, pretty-printed with sorted keys.
    static func state(_ stem: String) throws -> Data {
        let id = shortId(stem)
        let app = AssistantApp(channel: "beta", appVersion: "1.0.1", build: 135,
                               speed: kmh.contains(id) ? .kmh : .knots)
        // A Garmin's own recording arrives through the GDPR export, the door that names it.
        let door = stem.hasSuffix("_native") ? "gdpr" : "file"
        let data = AssistantState.session(app, row: try AssistantStateTests.row(stem, importSource: door),
                                          analysis: try DocumentRendererTests.analysis(stem))
        let json = try JSONSerialization.jsonObject(with: data)
        let pretty = try JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return Data((String(data: pretty, encoding: .utf8)! + "\n").utf8)
    }

    @Test func theSessionStatesMatchTheirFiles() throws {
        let stems = try Self.stems()
        try #require(stems.count >= 12)
        #expect(Set(stems.map(Self.shortId)).count == stems.count, "two sessions share an id")
        if CopyContractTests.isWriting {
            try FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        }
        let schema = try AssistantStateTests.schema()
        for stem in stems {
            let url = Self.dir.appendingPathComponent(Self.shortId(stem) + ".json")
            let data = try Self.state(stem)
            #expect(SchemaCheck.validate(try JSONSerialization.jsonObject(with: data),
                                         against: schema).isEmpty, "\(stem)")
            if CopyContractTests.isWriting {
                try data.write(to: url, options: .atomic)
                continue
            }
            let onDisk = try? Data(contentsOf: url)
            #expect(onDisk == data,
                    """
                    docs/copy/assistant/sessions/\(Self.shortId(stem)).json is out of step \
                    with the kit. Regenerate:
                      COPY_WRITE=1 swift test --filter AssistantSessionsExportTests
                    """)
        }
        for id in Self.kmh {
            #expect(stems.map(Self.shortId).contains(id), "km/h session \(id) is not in the corpus")
        }
    }
}
