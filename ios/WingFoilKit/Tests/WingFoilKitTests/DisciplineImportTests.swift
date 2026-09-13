import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// **Where an imported session's preset comes from** (docs/presentation.md, "Confirming the
/// discipline on import"): the recording's own `discipline` field, then the rider's declared
/// default, and the sport code never — plus the review model the confirmation sheet reads.
@Suite struct DisciplineImportTests {

    // MARK: - The precedence rule

    @Test func theRecordingsOwnFieldBeatsTheRidersDefault() {
        // The CleanJibe watch app said so. Nothing the rider set in Settings is evidence
        // against a recording that states its own discipline, and the review step never asks.
        #expect(Discipline.imported(tag: "wingfoil", riderDefault: .windsurfFin) == .wingfoil)
        #expect(Discipline.imported(tag: "windsurf", riderDefault: .wingfoil) == .windsurfFoil)
        #expect(Discipline.imported(tag: "windsurf_fin", riderDefault: .wingfoil) == .windsurfFin)
        #expect(!Discipline.isGuess(tag: "wingfoil"))
    }

    @Test func aRecordingThatSaysNothingGetsTheRidersDefault() {
        #expect(Discipline.imported(tag: nil) == .wingfoil)
        #expect(Discipline.imported(tag: nil, riderDefault: .windsurfFin) == .windsurfFin)
        #expect(Discipline.imported(tag: "", riderDefault: .windsurfFoil) == .windsurfFoil)
        // A tag this version has never heard of states nothing *about this question* either.
        #expect(Discipline.imported(tag: "kitefoil", riderDefault: .windsurfFin) == .windsurfFin)
        #expect(Discipline.isGuess(tag: nil))
        #expect(Discipline.isGuess(tag: "kitefoil"))
    }

    @Test func theRidersOwnAnswerStillWinsOverBoth() {
        // The per-session override (Log → "Analyse as", and the review sheet) is the rider
        // speaking about *this* session, which outranks both the file and his own habit.
        var row = SessionRow(id: "x", startDate: Date(), durationS: 60, sourceClass: "a")
        row.discipline = "wingfoil"
        row.disciplineOverride = "windsurfFin"
        #expect(row.analysisDiscipline == .windsurfFin)
    }

    @Test func theSportCodeNeverDecides() {
        // The corpus's own shape: every "…-windsurfen…" recording in it is a wingfoil
        // afternoon ridden under Garmin's windsurf profile (ADR-004). It is not an argument to
        // `imported`, which is how this is enforced rather than promised — so the only thing
        // this test can assert is the row it produces.
        var row = SessionRow(id: "x", startDate: Date(), durationS: 60, sourceClass: "b")
        row.sport = "windsurfing"
        row.disciplineGuessed = true
        #expect(row.analysisDiscipline == .wingfoil)
        // …and the code is not thrown away: it is what the review row shows as a hint.
        #expect(DisciplineReview.sportHint(row.sport)?.hasPrefix("Filed as windsurfing") == true)
    }

    // MARK: - What the import writes down

    private func makeIngestor() throws -> (SessionIngestor, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-disc-\(UUID().uuidString)/Sessions",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (SessionIngestor(database: try AppDatabase.inMemory(),
                                archive: SessionArchive(root: root)), root)
    }

    @Test func aWindsurfersImportIsReadAsWindsurfAndMarkedAsAGuess() async throws {
        var (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let url = try #require(allFixtureFITs().first, "no fixture FITs available")
        let data = try Data(contentsOf: url)
        ingestor.riderDiscipline = .windsurfFin

        guard case .imported(let row) = try await ingestor.ingest(
            fitData: data, filename: url.lastPathComponent, source: .file) else {
            Issue.record("expected a fresh import")
            return
        }

        // A corpus FIT carries no `discipline` field (only the CleanJibe watch app writes one),
        // so the rider's default answered — and the row says so, in both columns.
        if row.discipline == nil {
            #expect(row.analysisDiscipline == .windsurfFin)
            #expect(row.disciplineOverride == "windsurfFin")
            #expect(row.disciplineGuessed)
            // Analysed under the preset on the spot, not left stale for the next sweep.
            #expect(row.engineVersion == ingestor.analysisVersion(for: .windsurfFin))
            #expect(try await ingestor.reanalyzeStale() == 0)
        } else {
            // A CleanJibe recording states its own discipline and is never a guess.
            #expect(!row.disciplineGuessed)
            #expect(row.analysisDiscipline == Discipline.resolve(tag: row.discipline))
        }
    }

    @Test func aWingfoilRidersImportIsByteIdenticalToTheOldBehaviour() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let url = try #require(allFixtureFITs().first, "no fixture FITs available")
        let data = try Data(contentsOf: url)

        guard case .imported(let row) = try await ingestor.ingest(
            fitData: data, filename: url.lastPathComponent, source: .file) else {
            Issue.record("expected a fresh import")
            return
        }
        #expect(row.analysisDiscipline == .wingfoil)
        #expect(row.disciplineOverride == nil)
        #expect(row.engineVersion == AnalysisEngine.version)
    }

    @Test func lettingTheGuessStandCostsNoReanalysis() async throws {
        var (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let url = try #require(allFixtureFITs().first, "no fixture FITs available")
        ingestor.riderDiscipline = .windsurfFoil

        guard case .imported(let row) = try await ingestor.ingest(
            fitData: try Data(contentsOf: url), filename: url.lastPathComponent,
            source: .file) else {
            Issue.record("expected a fresh import")
            return
        }
        try #require(row.disciplineGuessed, "a corpus FIT states no discipline")
        let before = row.engineVersion

        try await ingestor.confirmDiscipline(for: [row])
        let after = try #require(try await ingestor.allSessions().first { $0.id == row.id })
        #expect(!after.disciplineGuessed)
        // Nothing else moved: same preset, same stamp, same numbers.
        #expect(after.analysisDiscipline == row.analysisDiscipline)
        #expect(after.engineVersion == before)
        #expect(DisciplineReview.pending(in: [after]).isEmpty)
    }

    @Test func changingItClearsTheGuessAndRederivesThatSession() async throws {
        var (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let url = try #require(allFixtureFITs().first, "no fixture FITs available")
        ingestor.riderDiscipline = .wingfoil

        guard case .imported(let row) = try await ingestor.ingest(
            fitData: try Data(contentsOf: url), filename: url.lastPathComponent,
            source: .file) else {
            Issue.record("expected a fresh import")
            return
        }
        try #require(row.disciplineGuessed, "a corpus FIT states no discipline")

        _ = try await ingestor.setDiscipline(.windsurfFin, for: row)
        let after = try #require(try await ingestor.allSessions().first { $0.id == row.id })
        #expect(!after.disciplineGuessed)
        #expect(after.analysisDiscipline == .windsurfFin)
        #expect(after.engineVersion == ingestor.analysisVersion(for: .windsurfFin))
    }

    // MARK: - The review model

    private func guessed(_ id: String, _ day: Double, sport: String? = nil,
                         preset: Discipline = .wingfoil) -> SessionRow {
        var row = SessionRow(id: id, startDate: Date(timeIntervalSince1970: day * 86_400),
                             durationS: 3_600, sourceClass: "b")
        row.sport = sport
        row.disciplineGuessed = true
        if preset != .wingfoil { row.disciplineOverride = preset.rawValue }
        return row
    }

    @Test func onlyTheUnconfirmedSessionsAreListedAndTheNewestComesFirst() {
        var stated = guessed("watch", 3)
        stated.discipline = "wingfoil"
        stated.disciplineGuessed = false           // the watch app said so
        var answered = guessed("answered", 4)
        answered.disciplineGuessed = false         // the rider said so
        let rows = [guessed("a", 1), stated, guessed("b", 2), answered]

        #expect(DisciplineReview.pending(in: rows).map(\.id) == ["b", "a"])
        // Skipped ones stop raising a banner but keep their `?` — nothing was confirmed.
        #expect(DisciplineReview.pending(in: rows, dismissed: ["b"]).map(\.id) == ["a"])
        #expect(DisciplineReview.pending(in: rows, dismissed: ["a", "b"]).isEmpty)
    }

    @Test func theExampleAndAWatchCardAreNeverAskedAbout() {
        // A demonstration nobody rode, and a summary card with no recording behind it: one
        // has no rider to ask and the other has nothing to re-derive.
        var example = guessed("example", 5)
        example.isExample = true
        var card = guessed("card", 6)
        card.isProvisional = true
        #expect(DisciplineReview.pending(in: [example, card]).isEmpty)
        #expect(DisciplineReview.banner(DisciplineReview.pending(in: [example, card])) == nil)
    }

    @Test func theBannerNamesThePresetTheSessionsWereActuallyReadUnder() {
        #expect(DisciplineReview.banner([]) == nil)
        #expect(DisciplineReview.banner([guessed("a", 1)])
                == "1 new session analysed as Wingfoil")
        #expect(DisciplineReview.banner([guessed("a", 1), guessed("b", 2)])
                == "2 new sessions analysed as Wingfoil")
        #expect(DisciplineReview.banner([guessed("a", 1, preset: .windsurfFin),
                                         guessed("b", 2, preset: .windsurfFin)])
                == "2 new sessions analysed as Windsurf fin")
        // A mixed batch cannot name one preset without naming it wrongly for half the list.
        #expect(DisciplineReview.banner([guessed("a", 1),
                                         guessed("b", 2, preset: .windsurfFoil)])
                == "2 new sessions analysed — check the discipline")
    }

    @Test func theHintIsTheSportCodeAndOnlyWhereItSaysSomething() {
        #expect(DisciplineReview.sportHint(nil) == nil)
        #expect(DisciplineReview.sportHint("") == nil)
        #expect(DisciplineReview.sportHint("running") == nil)
        #expect(DisciplineReview.sportHint("43")
                == "Filed as windsurfing — which is also how a Garmin files a wingfoil session")
        #expect(DisciplineReview.sportHint("windsurfing")
                == DisciplineReview.sportHint("43"))
        #expect(DisciplineReview.sportHint("kitesurfing") == "Filed as kitesurfing")
    }
}
