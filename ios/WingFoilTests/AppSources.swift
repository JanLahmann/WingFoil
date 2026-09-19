import Foundation

/// **The app's own source tree, as the tests can read it.**
///
/// A few rules about the app are about what the *code* says rather than about what a
/// function returns — which help topic every `?` button on every screen points at, for one.
/// There is no runtime list of those: a `HelpButton` knows its own topic and nothing
/// collects them. So the test reads the sources, the same way `CopyLintTests` and
/// `CopyContractTests` do in the kit.
///
/// `#filePath` is the only handle a test has on the checkout it was compiled from, and it
/// is baked in at compile time, so this resolves on the machine that built the bundle and
/// nowhere else. A run on another machine — or a sandbox that refuses the read — gets
/// `nil` and the caller says so rather than failing: a source scan that cannot see the
/// sources has proved nothing either way.
enum AppSources {

    /// `ios/WingFoil`, or nil when this bundle cannot read the checkout it came from.
    static var directory: URL? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // strip AppSources.swift -> WingFoilTests/
            .deletingLastPathComponent()   // -> ios/
            .appendingPathComponent("WingFoil")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path,
                                             isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return url
    }

    /// Every `.swift` file under it, contents included. Empty when the read is refused.
    static func swiftFiles() -> [(url: URL, text: String)] {
        guard let directory,
              let walk = FileManager.default.enumerator(at: directory,
                                                        includingPropertiesForKeys: nil)
        else { return [] }
        return walk.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .compactMap { url in
                (try? String(contentsOf: url, encoding: .utf8)).map { (url, $0) }
            }
            .sorted { $0.url.path < $1.url.path }
    }

    /// The `.someCase` tokens on every line that mentions one of `markers`.
    ///
    /// Deliberately a line scan and not a parser. The call sites it has to cover include a
    /// ternary — `HelpButton(topic: payload == .fit ? .shareFit : .shareCard)` — where two
    /// of the three tokens are topics and one is not; the caller keeps the tokens it
    /// recognises and drops the rest, which is safe because a topic id that did not exist
    /// would not have compiled in the first place.
    static func dotTokens(onLinesContaining markers: [String]) -> [(token: String, file: String)] {
        var found: [(String, String)] = []
        for file in swiftFiles() {
            for line in file.text.split(separator: "\n", omittingEmptySubsequences: false) {
                guard markers.contains(where: { line.contains($0) }) else { continue }
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else {
                    continue
                }
                for match in line.matches(of: /\.([A-Za-z][A-Za-z0-9_]*)/) {
                    found.append((String(match.1), file.url.lastPathComponent))
                }
            }
        }
        return found
    }
}
