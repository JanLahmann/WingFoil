import Foundation
import Testing
@testable import WingFoilKit

/// **"Not a session"** — docs/algorithms.md, engine 0.19.0. The Swift half of a rule the lab
/// owns (`wingfoil_lab.goldens.session_verdict`) and the web bundle re-states
/// (`library.py`'s `session_verdict`); the three have to agree to the digit, which is what
/// the shared threshold constants below are asserted for.
struct SessionVerdictTests {

    /// The thresholds are a contract, not a tuning knob: three implementations read them.
    @Test func theThresholdsAreTheOnesTheContractPrints() {
        #expect(SessionVerdict.maxDurationS == 120)
        #expect(SessionVerdict.maxDistanceM == 200)
    }

    @Test(arguments: [
        // The shape Jan's library filled up with on 13–14 Sep 2026: started on the beach,
        // stopped again. No foil time, no minutes, no metres.
        (0.0, 24.0, 0.0, false, SessionVerdict.Reason.tooShort),
        (0.0, 0.0, 0.0, false, SessionVerdict.Reason.tooShort),
        // Long enough, but the recorder never went anywhere — a watch left running in the
        // van. The distance branch is what catches that one.
        (0.0, 1800.0, 12.0, false, SessionVerdict.Reason.noDistance),
        // `<` on both floors, so the boundary value itself is a session.
        (0.0, 119.9, 200.0, false, SessionVerdict.Reason.tooShort),
        (0.0, 120.0, 199.9, false, SessionVerdict.Reason.noDistance),
    ])
    func theRuleCatchesARecordingThatWasNeverASession(
        _ foilTimeS: Double, _ durationS: Double, _ distanceM: Double,
        _ isSession: Bool, _ reason: SessionVerdict.Reason
    ) {
        let verdict = SessionVerdict.of(foilTimeS: foilTimeS, durationS: durationS,
                                        distanceM: distanceM)
        #expect(verdict.isSession == isSession)
        #expect(verdict.reason == reason)
    }

    @Test(arguments: [
        // Exactly on both floors.
        (0.0, 120.0, 200.0),
        // **The skunked afternoon**: never once up, and unarguably a session. This is the
        // case the conjunction exists to protect, and the reason the rule is not "no foil
        // time" on its own.
        (0.0, 4800.0, 2100.0),
        // Any foil time at all settles it before either floor is consulted — which is why
        // the two floors can be set generously.
        (0.1, 1.0, 0.0),
    ])
    func aSkunkedAfternoonIsStillAnAfternoon(_ foilTimeS: Double, _ durationS: Double,
                                             _ distanceM: Double) {
        let verdict = SessionVerdict.of(foilTimeS: foilTimeS, durationS: durationS,
                                        distanceM: distanceM)
        #expect(verdict.isSession)
        #expect(verdict.reason == nil)
    }

    /// The rule may not reach a single recording the project already calls a session —
    /// including the 60 s smoke fixture, which is *inside* the duration floor (59.0 s against
    /// 120) and is a session on its 30 s of foil time alone.
    @Test func everyCorpusGoldenIsASession() throws {
        let dir = testFixturesDir.appendingPathComponent("goldens")
        let goldens = ((try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasSuffix(".expected.json") }
        try #require(!goldens.isEmpty)
        for url in goldens {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            let summary = try #require((object as? [String: Any])?["summary"] as? [String: Any])
            #expect(summary["isSession"] as? Bool == true, "\(url.lastPathComponent)")
            #expect(summary["notASessionReason"] is NSNull, "\(url.lastPathComponent)")
        }
    }

    /// The words, once: the row's tag and the page's line (docs/presentation.md).
    @Test func theRiderIsToldItIsKeptAndWhyItIsNotCounted() {
        #expect(NotASessionNote.tag == "No riding detected")

        let line = NotASessionNote.line(reason: .tooShort, durationS: 24, distanceKm: 0)
        #expect(line.contains("0:24"))
        #expect(line.contains("0 m"))               // metres, not the "0.0 km" that caused it
        #expect(line.contains("kept"))
        // No engine vocabulary anywhere near the rider.
        for word in ["isSession", "foilTimeS", "success", "carried", "invalid", "deleted"] {
            #expect(!line.localizedCaseInsensitiveContains(word), "\(word) reached the rider")
        }

        let card = NotASessionNote.line(reason: .noRecording, durationS: 4200, distanceKm: 18)
        #expect(card.contains("has not arrived yet"))
    }
}
