import Foundation
import Testing
@testable import WingFoilKit

/// **The jump detector against the lab** (engine 0.29.0, docs/algorithms/jumps.md).
///
/// No committed recording holds a real jump, so the goldens cannot hold `JumpDetector` to
/// `jump.py`. `fixtures/synthetic/jumps.json` does: one 25 Hz wrist trace with six simulated
/// events, the speed, flight and turn spans around them, and the lab's verdict on each,
/// computed from the very (rounded) samples stored — written by
/// `lab/tools/make_jump_fixture.py`. Two jumps, one chop too short to be a candidate, and
/// one candidate per context gate.
@Suite struct JumpParityTests {

    private struct Fixture: Decodable {
        struct Expected: Decodable {
            struct J: Decodable {
                var startTs, endTs, airtimeS, heightM, sigmaM, takeoffG, impactG: Double
            }
            struct C: Decodable { var startTs: Double; var reason: String }
            var jumps: [J]
            var candidates: [C]
        }
        var t: [Double]
        var mag: [Double]
        var speedT: [Double]
        var speedMps: [Double]
        var flightSpans: [[Double]]
        var turnSpans: [[Double]]
        var expected: Expected
    }

    private func load() throws -> Fixture {
        let url = testFixturesDir.appendingPathComponent("synthetic/jumps.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func run(_ f: Fixture) -> JumpResult {
        JumpDetector.detect(times: f.t, magnitudes: f.mag,
                            flightSpans: f.flightSpans.map { ($0[0], $0[1]) },
                            turnSpans: f.turnSpans.map { ($0[0], $0[1]) },
                            speed: (f.speedT, f.speedMps))
    }

    @Test func jumpsMatchTheLab() throws {
        let f = try load()
        let res = run(f)
        #expect(res.jumps.count == f.expected.jumps.count)
        for (i, (e, a)) in zip(f.expected.jumps, res.jumps).enumerated() {
            let checks: [(String, Double, Double, Double)] = [
                ("startTs", a.tStart, e.startTs, 0.002),
                ("endTs", a.tEnd, e.endTs, 0.002),
                ("airtimeS", a.height.airtimeS, e.airtimeS, 1e-3),
                ("heightM", a.height.integratedM, e.heightM, 1e-3),
                ("sigmaM", a.height.sigmaM, e.sigmaM, 1e-3),
                ("takeoffG", a.takeoffG, e.takeoffG, 1e-3),
                ("impactG", a.impactG, e.impactG, 1e-3),
            ]
            for (key, actual, expected, tol) in checks {
                #expect(abs(actual - expected) <= tol,
                        "jumps[\(i)].\(key): \(actual) vs lab \(expected)")
            }
        }
    }

    @Test func candidatesMatchTheLabInOrder() throws {
        let f = try load()
        let res = run(f)
        #expect(res.candidates.map(\.reason.rawValue) == f.expected.candidates.map(\.reason))
        for (i, (e, a)) in zip(f.expected.candidates, res.candidates).enumerated() {
            #expect(abs(a.tStart - e.startTs) <= 0.002,
                    "candidates[\(i)].startTs: \(a.tStart) vs lab \(e.startTs)")
        }
    }

    /// Without the context the three context gates do not run (nil = no gate, the lab's
    /// synthetic-trace case): the gated events come back as jumps or as refractory.
    @Test func noContextMeansNoContextGates() throws {
        let f = try load()
        let res = JumpDetector.detect(times: f.t, magnitudes: f.mag)
        let reasons = Set(res.candidates.map(\.reason))
        #expect(!reasons.contains(.offFoil))
        #expect(!reasons.contains(.tooSlow))
        #expect(!reasons.contains(.insideTurn))
        #expect(res.jumps.count > f.expected.jumps.count)
    }

    /// The document carries the integrated height and the summary the highest of them.
    @Test func recordAndSummaryReadTheIntegratedHeight() throws {
        let res = run(try load())
        let records = res.jumps.map(JumpRecord.init)
        let summary = JumpSummary(records)
        #expect(summary.count == res.jumps.count)
        #expect(summary.highestM == res.jumps.map(\.height.integratedM).max())
        #expect(JumpSummary([]).highestM == nil)
    }

    /// A stored document from before 0.29.0 has neither key and decodes to nil, not to an
    /// empty list: "not measured" and "no jumps" stay two facts.
    @Test func olderSummaryDecodesWithoutJumps() throws {
        let json = #"{"foilTimeS":1,"foilPct":1,"flightCount":1,"longestFlightS":1,"maxFlightM":1,"distanceKm":1}"#
        let s = try JSONDecoder().decode(SessionSummary.self, from: Data(json.utf8))
        #expect(s.jumps == nil)
        let round = try JSONDecoder().decode(
            SessionSummary.self,
            from: JSONEncoder().encode({ var x = s; x.jumps = JumpSummary(count: 0, highestM: nil); return x }()))
        #expect(round.jumps == JumpSummary(count: 0, highestM: nil))
    }
}
