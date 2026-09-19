import Foundation
import Testing
@testable import WingFoilKit

/// **The crash block of the feedback mail**, from the shape MetricKit actually delivers.
///
/// The fixture is `fixtures/crash/metrickit-payload.json`: one crash, one hang and one
/// disk-write exception in Apple's own `jsonRepresentation()` layout, with a nested
/// `subFrames` chain and a second, unattributed thread — the two things the frame walk has
/// to get right. Nothing in this suite imports MetricKit; that is the point of the parsing
/// living in the kit.
@Suite struct CrashDigestTests {

    private var payload: Data {
        get throws {
            try Data(contentsOf: testFixturesDir
                .appendingPathComponent("crash/metrickit-payload.json"))
        }
    }

    private let arrived = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: Reading the payload

    @Test func allThreeKindsAreRead() throws {
        let digests = CrashLog.digests(fromPayloadJSON: try payload, receivedAt: arrived)
        #expect(digests.map(\.kind) == [.crash, .hang, .diskWrite])
    }

    /// The payload's own window, not the moment it arrived: a payload is delivered a day
    /// or so late, and a mail that stamped every crash with the delivery would place them
    /// all on the same afternoon.
    @Test func theStampIsThePayloadsOwn() throws {
        let digests = CrashLog.digests(fromPayloadJSON: try payload, receivedAt: arrived)
        #expect(digests.allSatisfy { $0.date != arrived })
        #expect(FeedbackReport.crashLines(digests, build: "75", zone: .gmt)[2]
                    .hasPrefix("2026-09-14 15:05"))
    }

    /// The deepest frame of the **attributed** thread. The fixture's root frame is `dyld`
    /// and its sub-frame is the app, which is the line worth printing; the second thread is
    /// unattributed and must not be the one that is read.
    @Test func theTopFrameIsTheDeepestFrameOfTheBlamedThread() throws {
        let crash = CrashLog.digests(fromPayloadJSON: try payload, receivedAt: arrived)[0]
        #expect(crash.topFrame == "WingFoil +0x1b523")
        #expect(crash.reason == "Namespace SIGNAL, Code 11")
        #expect(crash.build == "74")
    }

    /// A hang and a disk write state a measurement rather than a signal, and `MXUnit`
    /// arrives as a value and a unit.
    @Test func aHangSaysHowLongAndADiskWriteSaysHowMuch() throws {
        let digests = CrashLog.digests(fromPayloadJSON: try payload, receivedAt: arrived)
        #expect(digests[1].reason == "Hung for 4.5 s")
        #expect(digests[2].reason == "Wrote 1024 MB")
    }

    /// A payload whose shape has moved costs the field, never the mail.
    @Test func rubbishIsAnEmptyListAndNotAnError() {
        #expect(CrashLog.digests(fromPayloadJSON: Data("not json".utf8)).isEmpty)
        #expect(CrashLog.digests(fromPayloadJSON: Data("{}".utf8)).isEmpty)
        #expect(CrashLog.decode(Data("[".utf8)).isEmpty)
    }

    // MARK: The file

    @Test func theKeptListSurvivesARoundTrip() throws {
        let digests = CrashLog.digests(fromPayloadJSON: try payload, receivedAt: arrived)
        let data = try #require(CrashLog.encode(digests))
        #expect(CrashLog.decode(data) == digests)
    }

    /// MetricKit re-delivers: the same crash arrives in two daily payloads, and a mail that
    /// listed it twice would read as two failures.
    @Test func theSameCrashIsNotKeptTwice() throws {
        let digests = CrashLog.digests(fromPayloadJSON: try payload, receivedAt: arrived)
        #expect(CrashLog.merge(digests, with: digests).count == digests.count)
    }

    @Test func onlyTheLastTenAreKeptNewestFirst() {
        let many = (0..<14).map {
            CrashDigest(kind: .crash, date: Date(timeIntervalSince1970: Double($0) * 3600),
                        reason: nil, topFrame: "frame \($0)", build: "75")
        }
        let kept = CrashLog.merge([], with: many)
        #expect(kept.count == CrashLog.keepCount)
        #expect(kept.first?.topFrame == "frame 13")
        #expect(kept == kept.sorted { $0.date > $1.date })
    }

    // MARK: The section in the mail

    private func facts(build: String = "75", crashes: [CrashDigest]) -> FeedbackFacts {
        FeedbackFacts(
            app: .init(version: "1.0", build: build, isDev: false, engineVersion: "0.20.0"),
            phone: .init(model: "iPhone18,2", system: "iOS 26.0", locale: "en_DE"),
            watch: .init(garminModel: nil, garminAppVersion: nil, appleWatchPaired: nil,
                         healthImport: nil),
            library: .init(sessionCount: 3, sources: []),
            crashes: crashes)
    }

    @Test func theSectionNamesEveryKindAndEveryFrame() throws {
        let digests = CrashLog.digests(fromPayloadJSON: try payload, receivedAt: arrived)
        let lines = FeedbackReport.crashLines(digests, build: "75", zone: .gmt)
        #expect(lines == [
            "iOS collected these on this phone.",
            "Crashes 1 · Hangs 1 · Disk writes 1",
            "2026-09-14 15:05 · Crash · Namespace SIGNAL, Code 11 · WingFoil +0x1b523 "
                + "· build 74",
            "2026-09-14 15:05 · Hang · Hung for 4.5 s · WingFoil +0x321ce",
            "2026-09-14 15:05 · Disk write · Wrote 1024 MB · WingFoil +0xbcde",
        ])
    }

    /// The build is named only when it is **not** the one the mail is being written from:
    /// a tester who has updated since is often reporting something already fixed, and a
    /// build number repeated on every line would be noise on the common case.
    @Test func onlyAnOlderBuildIsNamed() throws {
        let digests = CrashLog.digests(fromPayloadJSON: try payload, receivedAt: arrived)
        let lines = FeedbackReport.crashLines(digests, build: "74", zone: .gmt)
        #expect(lines[2].hasSuffix("WingFoil +0x1b523"))
        #expect(lines[3].hasSuffix("build 75"))
    }

    /// Eleven lines at the very worst: the note, the counts, eight crashes and the tally of
    /// what was left out. A fact sheet longer than the report stops being read.
    @Test func theBlockStaysShortHoweverBadTheFortnight() {
        let many = (0..<CrashLog.keepCount).map {
            CrashDigest(kind: .crash, date: Date(timeIntervalSince1970: Double($0)),
                        reason: nil, topFrame: nil, build: "75")
        }
        let lines = FeedbackReport.crashLines(many, build: "75", zone: .gmt)
        #expect(lines.count == CrashLog.listCount + 3)
        #expect(lines.last == "2 older, not listed")
    }

    @Test func aPhoneThatHasNeverCrashedSaysNothingAtAll() {
        #expect(!FeedbackReport.body(facts(crashes: [])).contains("Recent crashes"))
    }

    /// The whole mail, from the fixture: the heading is there, it sits under the rule with
    /// the rest of the diagnostics, and the rider's own half is still on top.
    @Test func theMailCarriesTheBlockUnderTheRule() throws {
        let digests = CrashLog.digests(fromPayloadJSON: try payload, receivedAt: arrived)
        let body = FeedbackReport.body(facts(crashes: digests))
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        let heading = try #require(lines.firstIndex(of: "Recent crashes"))
        let rule = try #require(lines.firstIndex(of: Substring(FeedbackReport.Separator.rule)))
        #expect(rule < heading)
        #expect(body.contains("  iOS collected these on this phone."))
        #expect(body.contains("WingFoil +0x1b523"))
    }
}
