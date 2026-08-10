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
