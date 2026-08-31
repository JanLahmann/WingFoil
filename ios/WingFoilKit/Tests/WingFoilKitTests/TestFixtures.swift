import Foundation

/// Repo-local fixtures root (same resolution as FitParseTests: works from the checkout,
/// CI keeps the layout).
let testFixturesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // strip TestFixtures.swift -> WingFoilKitTests/
    .deletingLastPathComponent()   // -> Tests/
    .deletingLastPathComponent()   // -> WingFoilKit/
    .deletingLastPathComponent()   // -> ios/
    .deletingLastPathComponent()   // -> repo root
    .appendingPathComponent("fixtures")

/// Every .fit under fixtures/sessions plus fixtures/synthetic, sorted by filename.
func allFixtureFITs() -> [URL] {
    var fits: [URL] = []
    for sub in ["sessions", "synthetic"] {
        let dir = testFixturesDir.appendingPathComponent(sub)
        let found = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "fit" } ?? []
        fits.append(contentsOf: found)
    }
    return fits.sorted { $0.lastPathComponent < $1.lastPathComponent }
}

/// The FIT whose basename matches a golden stem (`<stem>.expected.json` ⇔ `<stem>.fit`).
func findFixtureFIT(stem: String) -> URL? {
    allFixtureFITs().first { $0.deletingPathExtension().lastPathComponent == stem }
}

/// The zone every fixture in the corpus was recorded in: CEST, +02:00.
///
/// Spelled once, here, because since engine 0.8.2 nothing in the presentation layer
/// defaults its `timeZone:` to the device's any more — the defaults were removed precisely
/// so that no caller could pick a zone by accident, and a test is a caller. Pinning it to
/// the corpus's own offset also makes every asserted clock string independent of the
/// machine running the suite, which is the property `presentationReadsTheSessionsOwnClock`
/// exists to prove.
let fixtureZone = TimeZone(secondsFromGMT: 2 * 3600)!
