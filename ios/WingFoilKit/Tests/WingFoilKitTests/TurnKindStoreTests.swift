import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// Schema v19: the outcome ladder **per turn kind** on every stored row, back-filled from the
/// `turn` child rows a pre-change library already holds (docs/presentation/trends-periods.md,
/// "The period card").
@Suite struct TurnKindStoreTests {

    /// A corpus FIT with jibes **and** tacks in it (52 and 2), so both ladders are exercised.
    /// Since engine 0.27.0 (ADR-037) its two aborted tacks are crashes that rounded up and the
    /// default reading has none, so it is read with the aborted-tack gates off — the 0.26.0
    /// reading, which is still a row a library can hold.
    static let stem = "2026-08-03-0741_nago-torbole-windsurfen_native"

    static var gatesOff: TurnConfig {
        var config = TurnConfig()
        config.abortAxisDeg = 0
        config.abortLuffDeg = 0
        return config
    }

    static func analysis() throws -> (SessionAnalysis, Date, Double) {
        let url = try #require(findFixtureFIT(stem: stem), "fixture \(stem) is missing")
        let raw = try FitSessionParser.parse(data: Data(contentsOf: url))
        let start = try #require(raw.startDate)
        let span = try #require(raw.samples.last.map { $0.t - raw.samples[0].t })
        return (try SessionSummarizer.analyze(raw, turnConfig: gatesOff), start, span)
    }

    /// A row the way a v18 build wrote it: the per-kind counts and flew-through shares, the
    /// ladder over every counted turn, and (optionally) the turn child rows.
    static func insertV18Row(_ db: Database, id: String, analysis: SessionAnalysis,
                             start: Date, span: Double, turns: Bool,
                             provisional: Bool = false) throws {
        let t = analysis.summary.turns
        try db.execute(sql: """
            INSERT INTO session (id, startDate, durationS, sourceClass, engineVersion,
                                 isExample, isProvisional, jibes, jibesSuccessful,
                                 jibesFlewThrough, tacks, tacksSuccessful, tacksFlewThrough,
                                 turnsCounted, turnsFlewThrough, turnsTouchdown, turnsFellIn)
            VALUES (?, ?, ?, 'b', ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [id, start, span, analysis.engineVersion, provisional,
                             t.jibes, t.jibesSuccessful, t.jibeOutcomes.flewThrough,
                             t.tacks, t.tacksSuccessful, t.tackOutcomes.flewThrough,
                             t.turnsCounted, t.outcomes.flewThrough, t.outcomes.touchdown,
                             t.outcomes.fellIn])
        if turns {
            for row in SessionDerivation.turns(analysis, sessionId: id) { try row.insert(db) }
        }
    }

    /// A v18 library opened by this build: the analysed row gets both ladders out of its
    /// own turn rows, equal to the engine's; a row whose turn rows are gone and a provisional
    /// row stay NULL; nothing is added or lost; and a second pass changes nothing.
    @Test func v19BackFillsTheLadderPerKindFromTheStoredTurns() throws {
        let (analysis, start, span) = try Self.analysis()
        let t = analysis.summary.turns
        try #require(t.jibes > 0 && t.tacks > 0, "the fixture needs a jibe and a tack")

        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v18")
        try queue.write { db in
            try Self.insertV18Row(db, id: "analysed", analysis: analysis, start: start,
                                  span: span, turns: true)
            try Self.insertV18Row(db, id: "orphan", analysis: analysis,
                                  start: start.addingTimeInterval(86_400), span: span,
                                  turns: false)
            try Self.insertV18Row(db, id: "card", analysis: analysis,
                                  start: start.addingTimeInterval(2 * 86_400), span: span,
                                  turns: true, provisional: true)
        }
        let database = try AppDatabase(queue)                       // ← runs v19

        let rows = try database.writer.read { db in
            try SessionRow.order(Column("startDate")).fetchAll(db)
        }
        #expect(rows.map(\.id) == ["analysed", "orphan", "card"])

        let analysed = rows[0]
        #expect(analysed.jibesTouchdown == t.jibeOutcomes.touchdown)
        #expect(analysed.jibesFellIn == t.jibeOutcomes.fellIn)
        #expect(analysed.tacksTouchdown == t.tackOutcomes.touchdown)
        #expect(analysed.tacksFellIn == t.tackOutcomes.fellIn)
        #expect(analysed.threeSixties == nil)
        let kinds = try #require(analysed.turnKinds)
        #expect(kinds == [
            TurnKindTally(kind: .jibe, flewThrough: t.jibeOutcomes.flewThrough,
                          touchdown: t.jibeOutcomes.touchdown, fellIn: t.jibeOutcomes.fellIn,
                          clean: t.jibesSuccessful),
            TurnKindTally(kind: .tack, flewThrough: t.tackOutcomes.flewThrough,
                          touchdown: t.tackOutcomes.touchdown, fellIn: t.tackOutcomes.fellIn),
        ])
        // The totals the row already carried are untouched.
        #expect(analysed.turnsFlewThrough == t.outcomes.flewThrough)
        #expect(analysed.jibes == t.jibes)

        // No turn rows that add up to its jibes: left for `apply(_:)`, never invented.
        #expect(rows[1].jibesTouchdown == nil)
        #expect(rows[1].turnKinds == nil)
        #expect(rows[2].turnKinds == nil)

        let again = try database.writer.write { db in try AppDatabase.backfillTurnKinds(db) }
        #expect(again == 0)
        #expect(try database.writer.read { db in try SessionRow.fetchCount(db) } == 3)
    }

    /// A fresh analysis fills the same columns the back-fill does — one answer by two paths.
    @Test func applyWritesTheSameLadderTheBackFillCounts() throws {
        let (analysis, start, span) = try Self.analysis()
        var row = SessionRow(startDate: start, durationS: span, sourceClass: "b")
        row.apply(analysis)
        let t = analysis.summary.turns
        #expect(row.turnKinds?.first { $0.kind == .jibe }?.outcomes
                == PeriodCard.Outcomes(flewThrough: t.jibeOutcomes.flewThrough,
                                       touchdown: t.jibeOutcomes.touchdown,
                                       fellIn: t.jibeOutcomes.fellIn))
        #expect(row.turnKinds?.first { $0.kind == .tack }?.count == t.tacks)
        #expect(row.threeSixties == nil)
    }

    /// Several rows' ladders summed per kind; a 360 entry only where one was counted.
    @Test func theKindsSumPerKind() {
        let a = [TurnKindTally(kind: .jibe, flewThrough: 5, touchdown: 2, fellIn: 1, clean: 4),
                 TurnKindTally(kind: .tack, flewThrough: 1, touchdown: 1, fellIn: 2)]
        let b = [TurnKindTally(kind: .jibe, flewThrough: 3, touchdown: 1, fellIn: 0, clean: nil),
                 TurnKindTally(kind: .tack, flewThrough: 0, touchdown: 0, fellIn: 1),
                 TurnKindTally(kind: .threeSixty, count: 2)]
        #expect(TurnKindTally.sum([a]).map(\.kind) == [.jibe, .tack])
        #expect(TurnKindTally.sum([a, b]) == [
            TurnKindTally(kind: .jibe, flewThrough: 8, touchdown: 3, fellIn: 1, clean: 4),
            TurnKindTally(kind: .tack, flewThrough: 1, touchdown: 1, fellIn: 3),
            TurnKindTally(kind: .threeSixty, count: 2),
        ])
    }
}
