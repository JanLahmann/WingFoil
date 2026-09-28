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

    /// **A land sport is not a session** (engine 0.26.0). Jan's Berlin Marathon read 98 % on
    /// foil at 10.65 kn: the sport is asked before the foil time.
    @Test(arguments: ["running", "cycling", "hiking", "mountaineering", "e_biking",
                      "motorcycling", "driving", "Running", "1", "17"])
    func aLandSportIsNotASessionWhateverItsSpeeds(_ sport: String) {
        let verdict = SessionVerdict.of(foilTimeS: 12000, durationS: 12300,
                                        distanceM: 42195, sport: sport)
        #expect(!verdict.isSession)
        #expect(verdict.reason == .landSport)
    }

    /// Walking, generic and training are how the CIQ app and the imports file real
    /// watersport sessions; a wing on skis or skates is still a wing.
    @Test(arguments: [nil, "walking", "generic", "training", "windsurfing", "kitesurfing",
                      "stand_up_paddleboarding", "11", "0", "43", "alpine_skiing",
                      "inline_skating"] as [String?])
    func walkingGenericAndTheWatersportsAreLeftToTheOtherRules(_ sport: String?) {
        let verdict = SessionVerdict.of(foilTimeS: 1800, durationS: 3600, distanceM: 12000,
                                        sport: sport)
        #expect(verdict.isSession)
        #expect(SessionVerdict.landSport(sport) == nil)
    }

    /// The list is the FIT profile's numbers, and the lab's (`LAND_SPORTS`).
    @Test func theLandSportsAreTheFitProfileNumbers() {
        #expect(SessionVerdict.landSports == ["running": 1, "cycling": 2, "mountaineering": 16,
                                              "hiking": 17, "e_biking": 21,
                                              "motorcycling": 22, "driving": 24])
        #expect(SessionVerdict.landSport("21") == "e_biking")
        #expect(SessionVerdict.landSport(" Cycling ") == "cycling")
    }

    /// The analysis carries the sport that decided, and the words name it.
    @Test func aRunIsToldItWasARun() throws {
        var raw = RawTrack()
        raw.capabilities.sport = "running"
        raw.capabilities.hasSpeed = true
        raw.capabilities.sampleRateHz = 1
        let epoch = Date(timeIntervalSince1970: 1_790_000_000)
        for t in stride(from: 0.0, through: 600, by: 1) {
            var s = RecordSample(t: t, timestamp: epoch.addingTimeInterval(t))
            s.speedMps = 5.5                    // a 3:00/km marathon pace clears the foil gate
            raw.samples.append(s)
        }
        let summary = SessionSummarizer.analyze(raw).summary
        #expect(!summary.isSession)
        #expect(summary.notASessionReason == .landSport)
        #expect(summary.landSport == "running")

        #expect(NotASessionNote.tag(for: .landSport) == "Not a watersport")
        #expect(NotASessionNote.tag(for: .tooShort) == NotASessionNote.tag)
        let line = NotASessionNote.line(reason: .landSport, durationS: nil, distanceKm: nil,
                                        sport: "e_biking")
        #expect(line.contains("recorded as e-biking"))
        #expect(line.contains("kept"))
        #expect(PresentationCopy.text("verdicts.notASession.lines.2",
                                      args: ["sport": "running"])?.contains("as running")
                == true)
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
            #expect(summary["landSport"] is NSNull, "\(url.lastPathComponent)")
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
