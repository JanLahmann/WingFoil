import Foundation
import Testing
@testable import WingFoilKit

/// **The dev workbench's pure half** (docs/presentation.md, "Dev workbench").
///
/// Three things have to hold or the page is worse than nothing. The trace must re-derive what
/// the engine decided — on a real fixture turn, against the record, with no disagreement, so a
/// disagreement on Jan's phone means something. The evidence table must cover exactly the spans
/// it claims to and survive a round trip through CSV. And the label scoring has to count
/// agreement the way a confusion table is read, including the empty case, where 0 % would be a
/// claim about a rider who has labelled nothing.
@Suite struct TurnWorkbenchTests {

    /// The one corpus fixture with an accelerometer *and* a barometer: the only one where the
    /// pump and wrist-under steps of the trace have anything to say.
    static let stem = "2026-08-07-0754_nago-torbole-windsurfen_ciq"

    static func session() throws -> (SessionAnalysis, RawTrack) {
        let url = try #require(findFixtureTrack(stem: stem))
        let track = try TrackParser.parse(data: try Data(contentsOf: url))
        return (SessionSummarizer.analyze(track), track)
    }

    // MARK: - The trace

    /// Every counted turn of a real session, re-derived — and **no step may disagree with the
    /// record**. This is the test the whole feature rests on: the trace is only worth reading
    /// because a mark beside a step means the re-derivation and the run genuinely differ.
    @Test func traceAgreesWithTheRecordOnEveryCountedTurn() throws {
        let (analysis, track) = try Self.session()
        let context = TurnWorkbench.context(analysis: analysis, track: track)
        let counted = analysis.turns.indices.filter { analysis.turns[$0].counted }
        #expect(counted.count > 10, "the fixture should carry a session's worth of turns")

        for index in counted {
            let trace = TurnTraceBuilder.trace(turnIndex: index, analysis: analysis,
                                               context: context)
            #expect(!trace.isEmpty)
            #expect(trace.assumedDefaults.isEmpty,
                    "a freshly analysed session echoes every turn parameter")
            let bad = trace.steps.filter(\.disagrees)
            let why = bad.map { step -> String in
                if case .disagrees(let derived, let record) = step.note {
                    return "\(step.title) derived \(derived), record \(record)"
                }
                return step.title
            }.joined(separator: "; ")
            #expect(bad.isEmpty, "turn \(index): \(why)")
        }
    }

    /// The trace covers the ladder: every turn gets the same rungs, in the same order, so the
    /// panel cannot quietly stop explaining a step.
    @Test func traceCarriesEveryRungInOrder() throws {
        let (analysis, track) = try Self.session()
        let context = TurnWorkbench.context(analysis: analysis, track: track)
        let index = try #require(analysis.turns.firstIndex { $0.counted })
        let titles = TurnTraceBuilder.trace(turnIndex: index, analysis: analysis,
                                            context: context).steps.map(\.title)
        #expect(titles == ["Entry window", "Sweep end", "Low point", "Outcome window",
                           "First off-foil sample", "Longest stop", "Pump burst", "Wrist under",
                           "Wind axis", "Quiet tail", "Outcome", "Clean"]
                || titles == ["Entry window", "Sweep end", "Low point", "Outcome window",
                              "First off-foil sample", "Pump burst", "Wrist under",
                              "Wind axis", "Quiet tail", "Outcome", "Clean"],
                "got \(titles)")
    }

    /// The instrumented window mirror must land on the **same sample** as the engine's, or the
    /// reason it prints belongs to a different instant. Checked on every counted turn.
    @Test func windowEndMirrorsTheEngine() throws {
        let (analysis, track) = try Self.session()
        let context = TurnWorkbench.context(analysis: analysis, track: track)
        let ev = try #require(context.evidence)
        for record in analysis.turns where record.counted {
            let turn = TurnWorkbench.turn(from: record)
            let mine = TurnTraceBuilder.windowEnd(turn, ev: ev, config: context.turn)
            #expect(mine.index == TurnDetector.windowEnd(turn, ev: ev, config: context.turn))
        }
    }

    /// The quiet tail mirror must reach the engine's own verdict on every jibe the engine
    /// actually asked the question of.
    @Test func quietTailMirrorsTheEngine() throws {
        let (analysis, track) = try Self.session()
        let context = TurnWorkbench.context(analysis: analysis, track: track)
        let ev = try #require(context.evidence)
        var asked = 0
        for record in analysis.turns
        where record.counted && record.type == "jibe" && record.success
            && record.outcome == "flew_through" {
            asked += 1
            let mine = TurnTraceBuilder.quietTail(record, ev: ev, config: context.turn,
                                                  ends: context.ends)
            let derived = mine.block?.rawValue ?? "quiet"
            let stored = record.cleanBlockedBy ?? "quiet"
            #expect(mine.block?.rawValue == record.cleanBlockedBy,
                    "turn at \(record.ts): \(derived) vs \(stored)")
        }
        #expect(asked > 0, "the fixture should have jibes the quiet tail is asked about")
    }

    /// A stored analysis from before a config field was echoed must be *named*, not guessed at
    /// in silence — the whole reason `assumedDefaults` exists.
    @Test func anEchoMissingAFieldIsNamedNotGuessed() throws {
        let (analysis, _) = try Self.session()
        var echo = analysis.config
        echo.minSpeedLag = nil
        echo.turnCleanQuietS = nil
        let (config, assumed) = TurnWorkbench.turnConfig(from: echo)
        #expect(assumed.contains("minSpeedLag"))
        #expect(assumed.contains("turnCleanQuietS"))
        #expect(config.minSpeedLagS == TurnConfig().minSpeedLagS)
        #expect(!assumed.contains("turnMinAngle"))
    }

    /// A tuned echo travels into the config the trace reads — the page prints the numbers the
    /// run used, never `TurnConfig()`'s.
    @Test func aTunedEchoReachesTheTraceConfig() throws {
        let (analysis, _) = try Self.session()
        var echo = analysis.config
        echo.turnFallStop = 7.5
        echo.turnContinueRate = 9
        let (config, assumed) = TurnWorkbench.turnConfig(from: echo)
        #expect(config.fallStopS == 7.5)
        #expect(config.continueRateDegS == 9)
        #expect(assumed.isEmpty)
    }

    // MARK: - The evidence table

    @Test func evidenceRowsCoverTheClaimedSpanAndBands() throws {
        let (analysis, track) = try Self.session()
        let context = TurnWorkbench.context(analysis: analysis, track: track)
        let index = try #require(analysis.turns.firstIndex { $0.counted })
        let record = analysis.turns[index]
        let rows = TurnEvidenceTable.rows(turnIndex: index, analysis: analysis, context: context)

        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { $0.t >= record.ts - TurnEvidenceTable.leadS })
        #expect(rows.allSatisfy { $0.t <= record.endTs + TurnEvidenceTable.trailS })
        #expect(rows == rows.sorted { $0.t < $1.t })
        // The sweep is always covered — the turn's own samples are why the table exists.
        #expect(rows.contains { $0.band == .sweep })
        #expect(rows.contains { $0.band == .entry })
        // `rt` is the turn's clock, so the sweep straddles zero.
        let sweep = rows.filter { $0.band == .sweep }
        #expect(sweep.first?.rt ?? 1 <= 0.001)
        // One band per row, most specific first.
        for row in rows where row.band == .sweep {
            #expect(row.t >= record.ts && row.t <= record.endTs)
        }
    }

    /// Sample counts, not shapes: the table must not drop a sample the ladder read, and must
    /// not invent one across a gap.
    @Test func evidenceRowsMatchTheEvidenceArraysOneForOne() throws {
        let (analysis, track) = try Self.session()
        let context = TurnWorkbench.context(analysis: analysis, track: track)
        let ev = try #require(context.evidence)
        let index = try #require(analysis.turns.firstIndex { $0.counted })
        let record = analysis.turns[index]
        let rows = TurnEvidenceTable.rows(turnIndex: index, analysis: analysis, context: context)
        let expected = ev.t.filter {
            $0 >= record.ts - TurnEvidenceTable.leadS && $0 <= record.endTs
                + TurnEvidenceTable.trailS
        }
        #expect(rows.count == expected.count)
        #expect(zip(rows, expected).allSatisfy { abs($0.t - $1) < 1e-9 })
    }

    @Test func csvHasOneHeaderAndOneRowPerSample() throws {
        let (analysis, track) = try Self.session()
        let context = TurnWorkbench.context(analysis: analysis, track: track)
        let index = try #require(analysis.turns.firstIndex { $0.counted })
        let rows = TurnEvidenceTable.rows(turnIndex: index, analysis: analysis, context: context)
        let lines = TurnEvidenceTable.csv(rows).split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == rows.count + 1)
        #expect(lines[0].hasPrefix("t_s,rt_s,doppler_kn,manoeuvre_kn"))
        // Every row has the same field count as the header — the one thing a spreadsheet
        // cannot recover from.
        let width = lines[0].split(separator: ",", omittingEmptySubsequences: false).count
        for line in lines.dropFirst() {
            #expect(line.split(separator: ",", omittingEmptySubsequences: false).count == width)
        }
    }

    @Test func csvFilenameIsSafeForAFilesystem() {
        #expect(TurnEvidenceTable.filename(session: "Nago/Torbole — 07:54", turnIndex: 12)
                == "nago-torbole-07-54-turn12.csv")
        #expect(TurnEvidenceTable.filename(session: "", turnIndex: 0) == "session-turn0.csv")
    }

    // MARK: - Labels

    @Test func scoringCountsAgreementAndFillsTheConfusionTable() {
        let entries = [
            labelled(0, verdict: .flewThrough, label: .flew),
            labelled(1, verdict: .flewThrough, label: .touched),
            labelled(2, verdict: .touchdown, label: .touched),
            labelled(3, verdict: .fellIn, label: .fell),
            labelled(4, verdict: .touchdown, label: .fell),
        ]
        let score = TurnLabelScoring.score(entries)
        #expect(score.total == 5)
        #expect(score.agreed == 3)
        #expect(score.agreedPct == 60)
        #expect(score.count(label: .flew, verdict: .flewThrough) == 1)
        #expect(score.count(label: .touched, verdict: .flewThrough) == 1)
        #expect(score.count(label: .fell, verdict: .touchdown) == 1)
        #expect(score.labelled(.touched) == 2)
        #expect(score.called(.touchdown) == 2)
        #expect(score.disagreements.map(\.turnIndex).sorted() == [1, 4])
    }

    /// Nothing labelled is not 0 % agreement — it is no answer, and the page has to be able
    /// to say so.
    @Test func anEmptyScoreHasNoPercentage() {
        let score = TurnLabelScoring.score([])
        #expect(score.isEmpty)
        #expect(score.agreedPct == nil)
        #expect(score.caption == "nothing labelled yet")
        // The table is still full of zeroes rather than missing rows, so the page draws a grid.
        #expect(score.confusion.count == TurnLabel.allCases.count)
    }

    @Test func labelsRoundTripThroughTheSheetAndTheCsv() throws {
        var sheet = TurnLabelSheet(sessionID: "abc")
        sheet[3] = .touched
        sheet[7] = .fell
        sheet[7] = nil
        #expect(sheet[3] == .touched)
        #expect(sheet[7] == nil)
        let data = try JSONEncoder().encode(sheet)
        let back = try JSONDecoder().decode(TurnLabelSheet.self, from: data)
        #expect(back == sheet)

        let csv = TurnLabelScoring.csv([labelled(3, verdict: .touchdown, label: .touched)])
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("session_id,session_title,session_start,turn_index"))
        // The engine's spelling, so the file reads beside `analysis.json`.
        #expect(lines[1].contains(",touched,touchdown,"))
    }

    /// A title with a comma in it must not become two columns.
    @Test func csvQuotesTheFreeTextColumns() {
        var entry = labelled(1, verdict: .fellIn, label: .fell)
        entry.sessionTitle = "Torbole, afternoon"
        let line = TurnLabelScoring.csv([entry]).split(separator: "\n")[1]
        #expect(line.contains("\"Torbole, afternoon\""))
    }

    private func labelled(_ index: Int, verdict: TurnOutcomeKind,
                          label: TurnLabel) -> LabelledTurn {
        LabelledTurn(sessionID: "s", sessionTitle: "session", startDate: Date(timeIntervalSince1970: 0),
                     turnIndex: index, ts: Double(index) * 60, type: "jibe",
                     verdict: verdict, clean: false, label: label)
    }

    // MARK: - What-if and the session diff

    /// The same analysis against itself is the honest null: no change, and every turn's card
    /// says the two runs are identical.
    @Test func aSessionDiffedAgainstItselfIsEmpty() throws {
        let (analysis, _) = try Self.session()
        let diff = TuningDiffBuilder.diff(tuned: analysis, base: analysis)
        #expect(diff.isEmpty)
        #expect(diff.changes.isEmpty)
        #expect(diff.headline == "Tuned vs default: nothing changed")

        let index = try #require(analysis.turns.firstIndex { $0.counted })
        let card = try #require(TurnWhatIf.make(turnIndex: index, tuned: analysis,
                                                base: analysis))
        #expect(card.identical)
        #expect(card.base != nil)
    }

    /// A real re-tune, run twice: a much longer fall threshold moves verdicts, and the diff has
    /// to name the turns it moved rather than only counting them.
    @Test func aRetunedSessionNamesTheTurnsThatMoved() throws {
        let url = try #require(findFixtureTrack(stem: Self.stem))
        let track = try TrackParser.parse(data: try Data(contentsOf: url))
        let base = SessionSummarizer.analyze(track)
        var overrides = TuningOverrides()
        overrides[.turnFallStop] = 15
        let configs = overrides.apply()
        let tuned = SessionSummarizer.analyze(track, flightConfig: configs.flight,
                                              turnConfig: configs.turn,
                                              flightEndConfig: configs.flightEnd)
        let diff = TuningDiffBuilder.diff(tuned: tuned, base: base)
        #expect(!diff.isEmpty)
        #expect(diff.verdictChanged > 0)
        #expect(diff.changes.count >= diff.verdictChanged)
        #expect(diff.changes == diff.changes.sorted { $0.ts < $1.ts })
        #expect(diff.headline.contains("verdict"))
        // A verdict change has both indices; only a removed turn may lack the tuned one.
        for change in diff.changes where change.kind != .removed {
            #expect(change.tunedIndex != nil)
        }
        for change in diff.changes where change.kind == .removed {
            #expect(change.tunedIndex == nil)
            #expect(change.defaultIndex != nil)
        }
    }

    /// The headline prints only what moved, with a real minus sign.
    @Test func theHeadlineOnlyPrintsWhatMoved() {
        let diff = TuningDiff(turnDelta: 3, jibeDelta: 3, tackDelta: 0, cleanDelta: -2,
                              verdictChanged: 4, cleanChanged: 0, changes: [])
        #expect(diff.headline == "Tuned vs default: +3 jibes, −2 clean, 4 verdicts changed")
    }

    /// A turn only the tuned run found gets a card with no second column — the tuning is what
    /// found it, and a column of dashes would read as "the default said nothing happened".
    @Test func aTurnTheDefaultRunNeverFoundHasNoSecondColumn() throws {
        let (analysis, _) = try Self.session()
        let index = try #require(analysis.turns.firstIndex { $0.counted })
        var empty = analysis
        empty.turns = []
        let card = try #require(TurnWhatIf.make(turnIndex: index, tuned: analysis, base: empty))
        #expect(card.base == nil)
        #expect(!card.identical)
    }
}
