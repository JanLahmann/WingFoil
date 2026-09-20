import Foundation
import Testing
import WingFoilKit
@testable import WingFoil

/// **The app's half of the crash block**: the file, and the fact that the mail reads it.
///
/// What a payload *means* is the kit's, and `CrashDigestTests` holds it against a fixture of
/// MetricKit's own JSON. What is left here cannot be said without a container: a file
/// written by one call and read back by another, and a feedback mail composed from it.
@Suite struct CrashDiagnosticsTests {

    /// A payload cut down to the one crash this suite needs. The full-sized fixture, with
    /// all three kinds and a nested frame chain, is `fixtures/crash/metrickit-payload.json`
    /// and belongs to the kit's suite, which is where the parsing lives.
    private let payload = Data("""
    {
      "timeStampEnd": "2026-09-14 15:05:00 +0000",
      "crashDiagnostics": [
        {
          "diagnosticMetaData": {
            "appBuildVersion": "75",
            "terminationReason": "Namespace SIGNAL, Code 11"
          },
          "callStackTree": {
            "callStacks": [
              {
                "threadAttributed": true,
                "callStackRootFrames": [
                  { "binaryName": "WingFoil", "offsetIntoBinaryTextSegment": 111907 }
                ]
              }
            ]
          }
        }
      ]
    }
    """.utf8)

    private func scratch() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func facts(crashes: [CrashDigest], watchRuns: Int? = nil) -> FeedbackFacts {
        FeedbackFacts(
            app: .init(version: "1.0", build: "75", isDev: false, engineVersion: "0.20.0"),
            phone: .init(model: "iPhone18,2", system: "iOS 26.0", locale: "en_DE"),
            watch: .init(garminModel: nil, garminAppVersion: nil, appleWatchPaired: nil,
                         healthImport: nil, garminCrashRuns: watchRuns),
            library: .init(sessionCount: 1, sources: []),
            crashes: crashes)
    }

    /// The test the audit asked for: a phone that has kept a crash sends a mail that
    /// carries it, top frame and all.
    @Test func theMailCarriesTheCrashSectionWhenOneWasKept() throws {
        let diagnostics = CrashDiagnostics(directory: try scratch())
        diagnostics.absorb(CrashLog.digests(fromPayloadJSON: payload))

        let body = FeedbackReport.body(facts(crashes: diagnostics.kept()))
        #expect(body.contains("Recent crashes"))
        #expect(body.contains("Crashes 1"))
        #expect(body.contains("WingFoil +0x1b523"))
        #expect(body.contains("Namespace SIGNAL, Code 11"))
        // The rider's permission over the whole block below the rule, said once, in the
        // kit's own words.
        #expect(body.contains(Copy.deleteAnyLine))
    }

    @Test func aPhoneThatHasNeverCrashedCarriesNoSection() throws {
        let diagnostics = CrashDiagnostics(directory: try scratch())
        #expect(diagnostics.kept().isEmpty)
        #expect(!FeedbackReport.body(facts(crashes: diagnostics.kept()))
            .contains("Recent crashes"))
    }

    /// The watch's half of the same block: its count of runs that never reached `onStop`,
    /// off the newest summary card (docs/channels.md, "Garmin watch: the crash breadcrumb").
    /// Three states, and the silent one is the one that must stay silent.
    @Test func theWatchsLostRunsAreCountedBesideThePhonesCrashes() throws {
        #expect(FeedbackReport.body(facts(crashes: [], watchRuns: 3))
            .contains("  Watch app: 3 runs ended without a save"))
        #expect(FeedbackReport.body(facts(crashes: [], watchRuns: 0))
            .contains("  Watch app: no crashes reported"))
        #expect(!FeedbackReport.body(facts(crashes: [])).contains("Watch app"))
    }

    /// The file is the whole persistence: a second instance over the same directory is
    /// what the next launch is.
    @Test func theKeptCrashesSurviveTheLaunchThatKeptThem() throws {
        let directory = try scratch()
        CrashDiagnostics(directory: directory)
            .absorb(CrashLog.digests(fromPayloadJSON: payload))
        let nextLaunch = CrashDiagnostics(directory: directory)
        #expect(nextLaunch.kept().count == 1)
        // …and the same payload arriving again is still one crash, not two: MetricKit
        // re-delivers.
        nextLaunch.absorb(CrashLog.digests(fromPayloadJSON: payload))
        #expect(nextLaunch.kept().count == 1)
    }

    /// The hook the screenshot pass shoots the accessibility sizes with (docs/testing.md).
    /// Its ladder is a pure mapping and is the one part of it that can be read without a
    /// simulator launch.
    @Test func theTextSizeHookReadsTheWholeLadder() {
        #expect(ScreenshotTextSize.named("xxxl") == .xxxLarge)
        #expect(ScreenshotTextSize.named("AX3") == .accessibility3)
        #expect(ScreenshotTextSize.named("ax5") == .accessibility5)
        #expect(ScreenshotTextSize.named("large") == .large)
        #expect(ScreenshotTextSize.named("enormous") == nil)
        #expect(ScreenshotTextSize.named(nil) == nil)
    }
}
