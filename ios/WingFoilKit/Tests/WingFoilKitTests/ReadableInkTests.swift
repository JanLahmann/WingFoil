import XCTest
@testable import WingFoilKit

/// Every readable ink against every ground, in both appearances — the 4.5 : 1 floor is a
/// property of the pair, so a nudge to either value that breaks it fails here.
final class ReadableInkTests: XCTestCase {

    func testContrastMatchesWcagReferencePoints() {
        XCTAssertEqual(ReadableInk.contrast(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
        XCTAssertEqual(ReadableInk.contrast(0x777777, 0xFFFFFF), 4.48, accuracy: 0.01)
        XCTAssertEqual(ReadableInk.contrast(0x123456, 0x123456), 1, accuracy: 0.0001)
    }

    func testEveryInkMeetsAaOnEveryGround() {
        for ink in [ReadableInk.secondary, ReadableInk.link] {
            for ground in ReadableInk.lightGrounds {
                XCTAssertGreaterThanOrEqual(ReadableInk.contrast(ink.light, ground),
                                            ReadableInk.minimumContrast,
                                            String(format: "%06X on %06X", ink.light, ground))
            }
            for ground in ReadableInk.darkGrounds {
                XCTAssertGreaterThanOrEqual(ReadableInk.contrast(ink.dark, ground),
                                            ReadableInk.minimumContrast,
                                            String(format: "%06X on %06X", ink.dark, ground))
            }
        }
    }

    /// What this replaced, so the reason stays on record: the system tertiary label and the
    /// accent mint on a light list are both under the floor.
    func testWhatItReplacedWasUnderTheFloor() {
        // tertiaryLabel (60,60,67 at 30 %) flattened onto the grouped background.
        XCTAssertLessThan(ReadableInk.contrast(0xC5C5C9, 0xF2F2F7), ReadableInk.minimumContrast)
        XCTAssertLessThan(ReadableInk.contrast(0x2EE6A8, 0xFFFFFF), ReadableInk.minimumContrast)
    }
}

/// **`.secondary` is retired in the app** (Jan, 30 Sep 2026: "Swap everywhere"). The system
/// secondary label is about 4.3 : 1 on a light grouped list — under the floor — so every word
/// and every meaningful symbol in `ios/WingFoil` is drawn in `.readableSecondary`. This reads
/// the app's sources and fails on a new bare `.secondary`.
///
/// Exempt without listing: a line that paints a ground or an outline (`.background(`,
/// `.fill(`, `.strokeBorder(`) — a tinted capsule behind a word is not the word's ink. Every
/// other survivor is in `allowed`, with its file, a fragment of the line and the reason.
final class SecondaryInkLintTests: XCTestCase {

    /// `…/ios/WingFoilKit/Tests/WingFoilKitTests/` is two levels below `ios/`.
    static let appRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("WingFoil")
    }()

    /// (path under ios/WingFoil, fragment of the line) — each a chart rule, a map track or a
    /// band fill: a line drawn quietly on purpose, never a word.
    static let allowed: [(file: String, fragment: String)] = [
        // The ink's own definition, which names the kit's pair.
        ("App/ReadableInk+Color.swift", "ReadableInk"),
        // Chart reference rules, dashed and at half weight under a trace.
        ("Features/Trends/TrendsView.swift", ".foregroundStyle(.secondary.opacity(0.5))"),
        ("Features/SessionDetail/TurnBaroStripView.swift", "Color.secondary.opacity(0.4)"),
        ("Features/SessionDetail/TurnDetailStripView.swift", "Color.secondary.opacity(0.5)"),
        ("Features/SessionDetail/FlightEndDetailView.swift", "Color.secondary.opacity(0.5)"),
        ("Features/SessionDetail/FlightEndDetailView.swift", "tint: Color.secondary.opacity(0.6)"),
        // The strip's entry band, a fill behind the trace.
        ("Features/SessionDetail/TurnStripChrome.swift", "static let entry = Color.secondary"),
        // The focus map's off-foil track, haloed by `TrackHalo`.
        ("Features/SessionDetail/FocusMapView.swift", "TrackHalo.ink(Color.secondary"),
        // The second arm of a capsule fill that opens on the line above.
        ("Features/SessionDetail/Dev/DevTurnWorkbenchView.swift", ": Color.secondary.opacity(0.12)))"),
    ]

    static let exemptPaints = [".background(", ".fill(", ".strokeBorder("]

    func testNoBareSecondaryForegroundInTheApp() throws {
        let pattern = try NSRegularExpression(pattern: #"\.secondary(?![A-Za-z0-9_])"#)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: Self.appRoot,
                                                                 includingPropertiesForKeys: nil))
        var scanned = 0
        var found: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            scanned += 1
            let rel = String(url.path.dropFirst(Self.appRoot.path.count + 1))
            let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            for (index, raw) in lines.enumerated() {
                let code = raw.components(separatedBy: "//").first ?? raw
                let range = NSRange(code.startIndex..., in: code)
                guard pattern.firstMatch(in: code, range: range) != nil else { continue }
                if Self.exemptPaints.contains(where: code.contains) { continue }
                if Self.allowed.contains(where: { rel == $0.file && code.contains($0.fragment) }) {
                    continue
                }
                found.append("\(rel):\(index + 1): \(code.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertGreaterThan(scanned, 50, "found no app sources under \(Self.appRoot.path)")
        XCTAssertTrue(found.isEmpty,
                      "bare .secondary in the app — use .readableSecondary, or allow-list a "
                      + "line that is never a word:\n" + found.joined(separator: "\n"))
    }
}
