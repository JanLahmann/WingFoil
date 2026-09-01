import Foundation
import Testing
@testable import WingFoilKit

/// The replay's commentary track: which instants get a line, what the line says, and how two
/// lines at one instant become one.
///
/// Asserted as a **whole script** against a decoded analysis golden, the way
/// `ReplayBeatsTests` asserts the whole tick list: the rules here are all about the shape of
/// a real afternoon — a run of clean jibes, a swim, a fastest two seconds in the middle of
/// it — and a synthetic fixture can be made to agree with any rule at all. Pinning the exact
/// sequence is also the only way a wording change, a rounding change or a lost milestone
/// fails a test rather than a screenshot.
@Suite struct ReplayCommentaryTests {

    private func golden(_ stem: String) throws -> SessionAnalysis {
        let url = testFixturesDir.appendingPathComponent("goldens/\(stem).expected.json")
        return try JSONDecoder().decode(SessionAnalysis.self, from: Data(contentsOf: url))
    }

    /// 2026-08-30 Torbole: 645 s, 2.6 km, ten counted jibes (eight flown, two swum), a dry
    /// streak of eight, two swims and a 2 s peak of 13.47 kn at 292 s.
    private func torbole() throws -> SessionAnalysis {
        try golden("2026-08-30-1407_nago-torbole-windsurfen_ciq")
    }

    /// 14:07 local at the north end of the lake, fixed so the opening line is the same
    /// string on a CI machine in UTC as on the phone that recorded it.
    private var torboleStart: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 30
        components.hour = 14; components.minute = 7
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar.date(from: components)!
    }

    /// The whole script, verbatim.
    @Test func theTorboleSessionCommentatesItself() throws {
        let script = ReplayCommentary.make(try torbole(), place: "Torbole",
                                           startedAt: torboleStart,
                                           timeZone: TimeZone(identifier: "Europe/Rome")!)

        #expect(script.map(\.t) == [0, 85, 151, 255, 278, 292, 320, 362, 399, 441, 477, 645])
        #expect(script.map(\.text) == [
            "Torbole, 14:07 — session start",
            // The first takeoff *is* the start of the longest flight here, so the two share
            // an instant and the plainer fact leads.
            "Flying! · Longest flight — 6:32",
            "First jibe — flew through",
            // The 3rd and 5th dry jibes are also streak records, and a line that said "3 dry
            // jibes · New streak — 3 dry jibes" would print the number twice.
            "New streak — 3 dry jibes",
            "New streak — 4 dry jibes",
            "Top speed — 13.47 kn over 2 s",
            "New streak — 5 dry jibes",
            "New streak — 6 dry jibes",
            "New streak — 7 dry jibes",
            "New streak — 8 dry jibes",
            // The swim at 467 is the jibe; the splash is its flight end ten seconds later.
            // It is also why nothing is said at 571: that tenth attempt was swum too, so the
            // dry count stops at eight and the session never reaches a tenth dry jibe.
            "First splash",
            "Session end — 10:45 · 2.6 km · 8 dry jibes",
        ])

        #expect(script.map(\.t) == script.map(\.t).sorted(), "must be in time order")
        #expect(Set(script.map(\.id)).count == script.count, "ids must be unique")
        // The merged instant keeps the more specific kind, because that is what the
        // caption's icon and ink read.
        #expect(script.first { $0.t == 85 }?.kind == .longestFlight)
        #expect(script.first { $0.t == 255 }?.kind == .streak(3))
        #expect(script.allSatisfy { !$0.text.isEmpty })
    }

    /// A jibe he swam out of never advances the count.
    ///
    /// The JPH rule (engine 0.7.0) said out loud: "a jibe he swam out of is one he did not
    /// make", so a commentary that reached ten by counting two swims would be congratulating
    /// a rider for falling. The fall is not swallowed — it is on the splash line, the
    /// channel WPH counts — it just does not move this number.
    @Test func aSwumJibeNeverAdvancesTheCount() throws {
        let analysis = try torbole()
        let counted = analysis.turns.filter { $0.counted && $0.type == "jibe" }
        let dry = counted.filter { $0.outcome != "fell_in" }
        #expect(counted.count == 10, "the fixture must contain ten counted jibes")
        #expect(dry.count == 8, "two of which were swum")

        let script = ReplayCommentary.make(analysis, timeZone: fixtureZone)
        // Ten attempts but only eight dry, so the tenth ordinal is never reached — and the
        // closing line totals the same eight the ordinals ran on.
        #expect(!script.contains { $0.text.contains("10 dry jibes") })
        #expect(script.last?.text.hasSuffix("· 8 dry jibes") == true)

        // Only the first ordinal is visible in its own right: the 3rd and the 5th land on
        // streak records that state the same number and absorb them.
        let ordinals = script.compactMap { milestone -> Int? in
            if case .jibe(let n) = milestone.kind { return n }
            return nil
        }
        #expect(ordinals == [1])
        // Whatever survives, an ordinal may only ever sit on a jibe that was flown out of.
        let dryTimes = Set(dry.map(\.ts))
        #expect(script.allSatisfy { milestone in
            guard case .jibe = milestone.kind else { return true }
            return dryTimes.contains(milestone.t)
        })
    }

    /// Without a name and a clock the opening line still exists — it just says less. A
    /// commentary that invented a location would be worse than one that admits it has none.
    @Test func theOpeningLineDegradesRatherThanInventing() throws {
        let script = ReplayCommentary.make(try torbole(), timeZone: fixtureZone)
        #expect(script.first?.text == "Session start")
        #expect(ReplayCommentary.startLine(place: "Torbole", startedAt: nil,
                                           timeZone: .current) == "Torbole — session start")
        #expect(ReplayCommentary.startLine(place: "  ", startedAt: nil,
                                           timeZone: .current) == "Session start")
    }

    /// The bookends follow the replay's own clock, not the engine's zero: a caption the
    /// slider cannot reach is a caption nobody hears.
    @Test func theBookendsSitOnTheSpanTheyAreGiven() throws {
        let script = ReplayCommentary.make(try torbole(), span: 12...600, timeZone: fixtureZone)
        #expect(script.first?.t == 12)
        #expect(script.last?.t == 600)
        #expect(script.last?.kind == .sessionEnd)
    }

    /// The streak walk is a second implementation of `TurnDetector.streaks` over the golden
    /// records, so the corpus holds the two against each other: the highest streak the
    /// commentary ever announces has to be the streak the engine reports.
    ///
    /// A session whose best run never reaches three announces nothing, which is not a
    /// disagreement — it is the floor doing its job, so the check is one-sided there.
    @Test(arguments: ["2026-08-30-1407_nago-torbole-windsurfen_ciq",
                      "2026-08-29-1440_nago-torbole-windsurfen_ciq"])
    func theStreakLinesAgreeWithTheEngine(_ stem: String) throws {
        let analysis = try golden(stem)
        let script = ReplayCommentary.make(analysis, timeZone: fixtureZone)
        let announced = script.compactMap { milestone -> Int? in
            if case .streak(let n) = milestone.kind { return n }
            return nil
        }
        let engine = analysis.summary.turns.longestDryStreak
        if engine >= ReplayCommentary.minStreak {
            #expect(announced.last == engine)
            // Only improvements, never a line per jibe.
            #expect(announced == announced.sorted())
            #expect(Set(announced).count == announced.count)
            #expect(announced.allSatisfy { $0 >= ReplayCommentary.minStreak })
        } else {
            #expect(announced.isEmpty)
        }
    }

    /// The counts that get a line. Spelled out rather than derived, because "and every tenth
    /// after that" is exactly the kind of rule an off-by-one hides in.
    @Test func onlyTheCountsWorthSayingGetALine() {
        #expect((1...25).filter(ReplayCommentary.isJibeMilestone) == [1, 3, 5, 10, 20])
        #expect((1...25).filter(ReplayCommentary.isSplashMilestone) == [1, 5, 10, 20])
    }

    /// The splash channel is the flight ends' `fell_in`, the same one WPH counts — so a swim
    /// in a straight line is a splash even though no turn was involved.
    @Test func splashesComeFromTheChannelWphCounts() throws {
        let analysis = try golden("2026-08-29-1440_nago-torbole-windsurfen_ciq")
        let wet = analysis.flightEnds.filter { $0.outcome == "fell_in" }.count
        #expect(wet > 0, "the fixture must contain swims")
        let script = ReplayCommentary.make(analysis, timeZone: fixtureZone)
        let splashes = script.compactMap { milestone -> Int? in
            if case .splash(let n) = milestone.kind { return n }
            return nil
        }
        #expect(splashes.first == 1)
        #expect(splashes.allSatisfy { $0 <= wet })
        // Nothing may be announced that did not happen.
        #expect(splashes.allSatisfy(ReplayCommentary.isSplashMilestone))
    }

    /// A recording that has a span but nothing in it still gets its two bookends: "you were
    /// out for eleven minutes and nothing was detected" is a fact, and an empty commentary
    /// would look like a broken feature rather than a quiet session.
    @Test func anEmptySessionKeepsItsBookendsAndNothingElse() throws {
        var analysis = try torbole()
        analysis.takeoffs = []
        analysis.flights = []
        analysis.turns = []
        analysis.flightEnds = []
        analysis.records = GP3SRecords()
        analysis.summary.turns = TurnSummary()
        let script = ReplayCommentary.make(analysis, timeZone: fixtureZone)
        #expect(script.map(\.kind) == [.sessionStart, .sessionEnd])
        #expect(script.last?.text == "Session end — 10:45 · 2.6 km")
    }

    /// No span, no session: a zero-length recording has no frame to put a caption in, and
    /// the events an old analysis still remembers are outside every frame there is.
    @Test func aZeroLengthRecordingSaysNothing() throws {
        var analysis = try torbole()
        analysis.summary.durationS = 0
        #expect(ReplayCommentary.make(analysis, span: 0...0, timeZone: fixtureZone).isEmpty)
        #expect(ReplayCommentary.make(analysis, timeZone: fixtureZone).isEmpty)
    }

    // MARK: - What a short clip has room to say

    /// The budget ladder, spelled out. The picker's three lengths are the only values that
    /// reach it in the app, but the boundaries are where an off-by-one would live.
    @Test func theBudgetIsAFunctionOfTheLengthAsked() {
        #expect(ReplayCommentary.budget(forTargetWallS: 10) == 4)
        #expect(ReplayCommentary.budget(forTargetWallS: 25) == 8)
        #expect(ReplayCommentary.budget(forTargetWallS: 60) == 12)
        // Below the first rung and above the last.
        #expect(ReplayCommentary.budget(forTargetWallS: 1) == 4)
        #expect(ReplayCommentary.budget(forTargetWallS: 14.99) == 4)
        #expect(ReplayCommentary.budget(forTargetWallS: 15) == 8)
        #expect(ReplayCommentary.budget(forTargetWallS: 39.99) == 8)
        #expect(ReplayCommentary.budget(forTargetWallS: 40) == 12)
        #expect(ReplayCommentary.budget(forTargetWallS: 89.99) == 12)
        #expect(ReplayCommentary.budget(forTargetWallS: 90) == nil)
        // "Full detail" is a pace, not a length, and budgets nothing away.
        #expect(ReplayCommentary.budget(forTargetWallS: nil) == nil)
        #expect(ReplayCommentary.budget(forTargetWallS: 0) == nil)
    }

    /// **The order the session gets cut in**, watched one line at a time on the Torbole
    /// afternoon. Twelve down to one: the two bookends outlive every limit, then the top
    /// speed, the longest flight, the best streak of the day, the first splash and the first
    /// jibe — and only then the run-up streaks, earliest first.
    ///
    /// Pinned as a sequence rather than as three spot checks because the property that matters
    /// is that it is a *priority*: what survives at four must be a subset of what survives at
    /// five, or "keep the best four" would mean something different at every length.
    @Test func theScriptIsCutInAKnownOrder() throws {
        let script = try torbole()
        let full = ReplayCommentary.make(script, timeZone: fixtureZone)
        #expect(full.count == 12)

        let byLimit = (0...12).map { ReplayCommentary.pruned(full, keeping: $0).map(\.id) }

        // The bookends survive a limit of zero: a clip that opened and never closed would be
        // worse than a silent one.
        #expect(byLimit[0] == ["start", "end"])
        #expect(byLimit[1] == ["start", "end"])
        #expect(byLimit[2] == ["start", "end"])
        #expect(byLimit[3] == ["start", "top-speed", "end"])
        #expect(byLimit[4] == ["start", "longest-flight", "top-speed", "end"])
        #expect(byLimit[5] == ["start", "longest-flight", "top-speed", "streak-8", "end"])
        // The two firsts are one tier, and the tie inside it goes the way the collision rule
        // already ranks them: a swim is a more specific thing to say than a count.
        #expect(byLimit[6] == ["start", "longest-flight", "top-speed", "streak-8", "splash-1",
                               "end"])
        #expect(byLimit[7] == ["start", "longest-flight", "jibe-1", "top-speed", "streak-8",
                               "splash-1", "end"])
        // From here it is the leftovers, by the collision rule's own rank and then by time:
        // the four remaining streak records, earliest first.
        #expect(byLimit[8] == ["start", "longest-flight", "jibe-1", "streak-3", "top-speed",
                               "streak-8", "splash-1", "end"])
        #expect(byLimit[12] == full.map(\.id))

        // Monotone: every list is a subset of the next one up.
        for (smaller, larger) in zip(byLimit, byLimit.dropFirst()) {
            #expect(Set(smaller).isSubset(of: Set(larger)),
                    "\(smaller) must survive into \(larger)")
        }
        // And always in time order, whatever the limit — the cut selects, it never reorders.
        for kept in byLimit {
            let times = full.filter { kept.contains($0.id) }.map(\.t)
            #expect(times == times.sorted())
        }
    }

    /// A limit at or above the count is not a cut at all — the same array back, identical.
    @Test func aScriptThatFitsIsLeftAlone() throws {
        let full = ReplayCommentary.make(try torbole(), timeZone: fixtureZone)
        #expect(ReplayCommentary.pruned(full, keeping: 12) == full)
        #expect(ReplayCommentary.pruned(full, keeping: 99) == full)
        #expect(ReplayCommentary.pruned(full, keeping: nil) == full)
        #expect(ReplayCommentary.pruned([], keeping: 4).isEmpty)
    }

    /// The best streak is the one that survives, not the first or the nearest — a session that
    /// went 3, 5, 8 has one piece of news in it and it is the eight.
    @Test func theStreakThatSurvivesIsTheRecord() throws {
        let full = ReplayCommentary.make(try torbole(), timeZone: fixtureZone)
        let kept = ReplayCommentary.pruned(full, keeping: 5)
        let streaks = kept.compactMap { milestone -> Int? in
            if case .streak(let n) = milestone.kind { return n }
            return nil
        }
        #expect(streaks == [8])
        #expect(full.compactMap { milestone -> Int? in
            if case .streak(let n) = milestone.kind { return n }
            return nil
        } == [3, 4, 5, 6, 7, 8])
    }

    /// What the bubble shows: the line the playhead has most recently passed, never one it
    /// is about to reach — a caption that arrived before its jibe would be a spoiler.
    @Test func theCurrentLineIsTheOneAlreadyPassed() throws {
        let script = ReplayCommentary.make(try torbole(), timeZone: fixtureZone)
        #expect(ReplayCommentary.current(at: -1, in: script) == nil)
        #expect(ReplayCommentary.current(at: 0, in: script)?.kind == .sessionStart)
        #expect(ReplayCommentary.current(at: 291.9, in: script)?.t == 278)
        #expect(ReplayCommentary.current(at: 292, in: script)?.kind == .topSpeed)
        #expect(ReplayCommentary.current(at: 10_000, in: script)?.kind == .sessionEnd)
    }
}
