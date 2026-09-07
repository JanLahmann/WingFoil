import Foundation
import Testing
@testable import WingFoilKit

/// The replay's tick marks: which instants get one, in which order, and how the skip
/// buttons walk them.
///
/// Asserted against a decoded analysis golden rather than a hand-built fixture, for the
/// same reason `presentationGoldensPinEveryMarkerAndFilterCount` does: the rules that
/// matter here are about a real session's turns and flights, and a synthetic one can be
/// made to agree with any rule at all.
@Suite struct ReplayBeatsTests {

    private func golden(_ stem: String) throws -> SessionAnalysis {
        let url = testFixturesDir.appendingPathComponent("goldens/\(stem).expected.json")
        return try JSONDecoder().decode(SessionAnalysis.self, from: Data(contentsOf: url))
    }

    /// 2026-08-30 Torbole: two flights, ten counted jibes (eight flown, two swum), a 2 s
    /// peak at 292 s, and a longest flight that starts on the first takeoff.
    private func torbole() throws -> SessionAnalysis {
        try golden("2026-08-30-1407_nago-torbole-windsurfen_ciq")
    }

    @Test func beatsCoverTheEventsWorthWatching() throws {
        let beats = ReplayBeats.make(try torbole())

        #expect(beats.map(\.t) == [85, 151, 222, 255, 278, 292, 320, 362, 399, 441, 467,
                                   542, 571])
        #expect(beats.map(\.t) == beats.map(\.t).sorted(), "beats must be in time order")
        #expect(Set(beats.map(\.id)).count == beats.count, "ids must be unique")

        // The first takeoff and the longest flight are the same instant; only the more
        // specific of the two survives it.
        #expect(beats.first?.kind == .longestFlight)
        #expect(beats.first?.label == "Longest flight")
        #expect(!beats.contains { $0.id == "takeoff-0" })
        #expect(beats.contains { $0.id == "takeoff-1" && $0.t == 542 })

        // The 2 s peak, at its own window's start rather than at a turn near it.
        let record = try #require(beats.first { $0.kind == .record })
        #expect(record.t == 292)
        #expect(record.label == "Best 2 s")

        // Every jibe carries its verdict, which is what the tick's colour reads.
        let jibes = beats.filter { if case .jibe = $0.kind { return true }; return false }
        #expect(jibes.count == 10)
        #expect(jibes.filter { $0.kind == .jibe(.fellIn) }.map(\.t) == [467, 571])
        #expect(jibes.filter { $0.kind == .jibe(.flewThrough) }.count == 8)
        #expect(jibes.first?.label == "Jibe · flew through")
        #expect(beats.allSatisfy { !$0.label.isEmpty })
    }

    /// A bear-away is a course change, not a maneuver — the same rule the map's markers
    /// follow. Nothing uncounted may become a beat.
    @Test func onlyCountedJibesBecomeBeats() throws {
        // The longer 29 Aug session, because the 30 Aug one is ten jibes and nothing else —
        // it cannot prove that anything is being left out.
        let analysis = try golden("2026-08-29-1440_nago-torbole-windsurfen_ciq")
        let counted = analysis.turns.filter { $0.counted && $0.type == "jibe" }
        #expect(counted.count < analysis.turns.count, "the fixture must contain non-jibes")
        let beats = ReplayBeats.make(analysis)
        for turn in analysis.turns where !turn.counted || turn.type != "jibe" {
            #expect(!beats.contains { $0.t == turn.ts && isJibe($0) },
                    "an uncounted or non-jibe turn at \(turn.ts) got a beat")
        }
    }

    private func isJibe(_ beat: ReplayBeat) -> Bool {
        if case .jibe = beat.kind { return true }
        return false
    }

    /// The skip buttons: strictly past the playhead in both directions, and idempotent at
    /// the two ends so holding one down does not wrap the replay around.
    @Test func skipWalksTheBeatsInBothDirections() throws {
        let beats = ReplayBeats.make(try torbole())

        #expect(ReplayBeats.beat(after: 0, in: beats)?.t == 85)
        #expect(ReplayBeats.beat(after: 85, in: beats)?.t == 151)
        #expect(ReplayBeats.beat(before: 151, in: beats)?.t == 85)
        #expect(ReplayBeats.beat(before: 85, in: beats) == nil)
        #expect(ReplayBeats.beat(after: 571, in: beats) == nil)

        // A playhead a hair off a beat — where 20 Hz playback leaves it — still counts as
        // being on that beat, so "next" advances rather than snapping back to it.
        #expect(ReplayBeats.beat(after: 85.2, in: beats)?.t == 151)
        #expect(ReplayBeats.beat(before: 84.9, in: beats) == nil)

        // Walking forward from the start visits every beat exactly once.
        var visited: [Double] = []
        var cursor = -1.0
        while let next = ReplayBeats.beat(after: cursor, in: beats) {
            visited.append(next.t)
            cursor = next.t
        }
        #expect(visited == beats.map(\.t))
    }

    /// A recording with no flights, no counted turns and no record window has nothing to
    /// skip to — and must say so with an empty list rather than a tick at zero.
    @Test func aSessionWithNothingInItHasNoBeats() throws {
        var analysis = try torbole()
        analysis.takeoffs = []
        analysis.flights = []
        analysis.turns = []
        analysis.records = GP3SRecords()
        #expect(ReplayBeats.make(analysis).isEmpty)
    }
}
