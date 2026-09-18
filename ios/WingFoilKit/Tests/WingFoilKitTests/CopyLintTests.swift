import Foundation
import Testing
@testable import WingFoilKit

/// **The two copy lints, run where a kit author will see them.**
///
/// `docs/copy/check_voice.py` holds every rider sentence to `docs/voice.md` — one thought
/// per sentence, no dash, no semicolon, no parenthesis, none of the banned shapes, no date
/// or version typed by hand, and a paragraph inside its budget (40 words, 25 in a Settings
/// or Import footer). `docs/copy/check_duplicates.py` holds pattern F: one sentence, one
/// home, across the kit's `Help/` and `Presentation/` and the app's `Features/`.
///
/// Both read the sources rather than the built product, so they can run from here, and they
/// have to: the kit is where most of those sentences are written, and `swift test` is what
/// a kit author runs. `web/tools/verify_links.py` runs the same two for a web change.
///
/// **A machine without python3 skips rather than fails.** The lints are the authority; a
/// missing interpreter is not a copy problem, and a red suite that means "this machine has
/// no python" teaches an author to ignore the suite.
@Suite struct CopyLintTests {

    /// `…/ios/WingFoilKit/Tests/WingFoilKitTests/` is five levels below the repository root.
    static let repoRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    /// The interpreter, or nil on a machine that has none. The three paths are where macOS,
    /// a python.org install and Homebrew put it.
    static let python: String? = ["/usr/bin/python3", "/usr/local/bin/python3",
                                 "/opt/homebrew/bin/python3"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Runs one lint from the repository root: its exit status and everything it printed.
    static func run(_ script: String) throws -> (status: Int32, output: String) {
        let python = try #require(Self.python)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [repoRoot.appendingPathComponent(script).path]
        process.currentDirectoryURL = repoRoot
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // Read before waiting: the lints print more than a pipe buffer holds.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    @Test(.enabled(if: CopyLintTests.python != nil,
                   "python3 is not on this machine, so the voice lint is skipped"))
    func everyRiderSentenceIsInsideTheVoice() throws {
        let result = try Self.run("docs/copy/check_voice.py")
        #expect(result.status == 0, """
                docs/copy/check_voice.py failed. Split the sentence or the paragraph, never \
                compress it, and give every cut fact a home (docs/voice.md, rule 10):

                \(result.output)
                """)
    }

    @Test(.enabled(if: CopyLintTests.python != nil,
                   "python3 is not on this machine, so the duplicate lint is skipped"))
    func noSentenceHasTwoHomesInTheApp() throws {
        let result = try Self.run("docs/copy/check_duplicates.py")
        #expect(result.status == 0, """
                docs/copy/check_duplicates.py failed. Put the sentence in one place — \
                WingFoilKit's `Copy` enum is the home for the lines two screens share — \
                and reference it from both (docs/review-checklist.md, pattern F):

                \(result.output)
                """)
    }
}
