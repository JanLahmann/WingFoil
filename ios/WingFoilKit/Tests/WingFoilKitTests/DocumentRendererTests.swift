import Foundation
import Testing
@testable import WingFoilKit

/// **The renderers, read off the presentation document** (ADR-033, round 2).
///
/// `PresentationTests` pins what each surface *says*; `GoldenTests` pins the document
/// against the lab's byte for byte. This is the join between them: a fixture's document,
/// rendered through the view models the phone draws, against the numbers the fixture has
/// always carried. It is what would fail if a renderer quietly went back to reading the
/// analysis — the strings would still be right and the fact would have two owners again.
///
/// One fixture is named throughout — `2026-08-03-1440`, the Torbole afternoon the
/// screenshots are taken of — so a reworded label fails here with the sentence in the
/// message rather than in a pixel diff.
@Suite struct DocumentRendererTests {

    static let stem = "2026-08-03-1440_nago-torbole-windsurfen_native"

    /// One golden analysis, decoded — the same source `GoldenTests` builds its documents
    /// from, so this suite and that one cannot be looking at different afternoons.
    static func analysis(_ stem: String) throws -> SessionAnalysis {
        let url = testFixturesDir.appendingPathComponent("goldens/\(stem).expected.json")
        return try JSONDecoder().decode(SessionAnalysis.self, from: Data(contentsOf: url))
    }

    static func document(_ stem: String) throws -> PresentationValue {
        PresentationDocument.build(try analysis(stem))
    }

    /// Every corpus fixture's document, in the order the goldens sit on disk.
    static func everyDocument() throws -> [(stem: String, document: PresentationValue)] {
        let dir = testFixturesDir.appendingPathComponent("presentation")
        let files = ((try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasSuffix(".expected.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { url in
            let stem = url.lastPathComponent.replacingOccurrences(of: ".expected.json",
                                                                  with: "")
            return (stem, try document(stem))
        }
    }

    // MARK: - (a) the key-metrics block, and the card that is the block

    /// **The block a rider reads, verbatim.**
    ///
    /// Every string here was produced by `KeyMetrics.make(summary:records:)` out of the
    /// analysis before round 2 and is produced by `KeyMetrics.make(block:)` out of the
    /// document now. They are the same strings, which is the whole claim of the round: the
    /// facts moved, the screen did not.
    @Test func theKeyMetricsBlockRendersTheDocument() throws {
        let block = KeyMetrics.make(block: try Self.document(Self.stem)["block"] ?? .null)

        #expect(block.basics.map(\.key) == ["duration", "distance", "avgSpeed"])
        #expect(block.basics.map(\.label) == ["duration", "distance", "avg speed"])
        #expect(block.basics[0].value == "1:59 h")
        #expect(block.basics[1].value == "17.5 km")

        #expect(block.maxSpeed.label == "max 2 s")
        #expect(block.speedExtras.map(\.label) == ["5×10 s", "alpha 500"])

        let tally = try #require(block.tally)
        #expect(tally.label == "flew · touchdown · fell")
        #expect(tally.caption == "of 18 jibes · 0 clean")
        #expect(tally.total == 18)
        // No tack ladder on this afternoon, and the falls cell is the *session*: the tally
        // above it is the jibes and says so (docs/algorithms/rates.md).
        #expect(block.tacks == nil)

        let falls = try #require(block.falls)
        #expect(falls.label == "fell in")
        #expect(falls.value == "11")
        #expect(falls.caption == "10 in a turn · 1 in a straight line")

        let streaks = try #require(block.streaks)
        #expect(streaks.label == "best streaks")
        #expect(streaks.value == "1 flew · 4 dry")

        #expect(block.rates.map(\.key) == ["jph", "cph", "wph"])
        #expect(block.rates.map(\.label) == ["JPH · dry jibes per hour",
                                             "CPH · clean jibes per hour",
                                             "WPH · swims per hour"])
        #expect(block.rates.map(\.value) == ["5.4", "0.0", "6.6"])
    }

    /// **The card is the block, minus the two composites.** It was the document's own rule
    /// before it was a renderer's, and `card.tiles` *are* `block` cells by construction —
    /// so this asserts that the Swift card and the document's card agree on which keys
    /// survive, on every fixture rather than on one.
    @Test func theCardCarriesExactlyTheBlockTheDocumentSays() throws {
        for (stem, document) in try Self.everyDocument() {
            let tiles = (document["card"]?["tiles"]?.arrayValue ?? [])
                .compactMap { $0["key"]?.stringValue }
            let stats = ShareCardStats.stats(from: KeyMetrics.make(block: document["block"]
                                                                   ?? .null),
                                             preset: .complete)
            #expect(stats.map(\.key) == tiles,
                    "\(stem): the card's tiles are not the document's, in its order")

            // And a preset may only drop: `lean` is a subset, never a substitution.
            let lean = ShareCardStats.stats(from: KeyMetrics.make(block: document["block"]
                                                                  ?? .null), preset: .lean)
            #expect(Set(lean.map(\.key)).isSubset(of: Set(tiles)),
                    "\(stem): lean invented a tile")
            let leanKeys = Set((document["card"]?["leanKeys"]?.arrayValue ?? [])
                .compactMap(\.stringValue))
            #expect(Set(lean.map(\.key)) == Set(tiles).intersection(leanKeys),
                    "\(stem): lean is not the document's lean set")
        }
    }

    /// A tile is its block cell, word for word. A card that reworded one would be a second
    /// vocabulary, which is the defect `ShareCardStats` was written to stop.
    @Test func everyTileIsItsBlockCellVerbatim() throws {
        let block = KeyMetrics.make(block: try Self.document(Self.stem)["block"] ?? .null)
        let stats = ShareCardStats.stats(from: block, preset: .complete)
        let byKey = Dictionary(uniqueKeysWithValues: stats.map { ($0.key, $0) })

        for metric in block.basics + block.speedExtras + [block.maxSpeed] {
            guard let stat = byKey[metric.key] else { continue }
            #expect(stat.label == metric.label)
            #expect(stat.value == metric.value)
            #expect(stat.caption == metric.caption)
        }
        let tallyStat = try #require(byKey[ShareCardStats.Key.tally])
        let tally = try #require(block.tally)
        #expect(tallyStat.label == tally.label)
        #expect(tallyStat.value == "3 · 6 · 9")
        #expect(tallyStat.caption == tally.caption)
    }

    /// **The unit is the renderer's, and only the renderer's.** One document, two riders:
    /// the numbers a knots reader and a km/h reader see are the same measurement, and
    /// nothing in the document had to know which.
    @Test func oneDocumentServesBothSpeedUnits() throws {
        let document = try Self.document(Self.stem)
        // `Speed.override` rather than `Speed.unit`: a task-local, so asking for km/h here
        // does not tell every other test running beside this one.
        let knots = Speed.$override.withValue(.knots) {
            KeyMetrics.make(block: document["block"] ?? .null)
        }
        let kmh = Speed.$override.withValue(.kmh) {
            KeyMetrics.make(block: document["block"] ?? .null)
        }

        #expect(knots.maxSpeed.value.hasSuffix("kn"))
        #expect(kmh.maxSpeed.value.hasSuffix("km/h"))
        // Everything that is not a speed is untouched by the switch.
        #expect(knots.basics[0].value == kmh.basics[0].value)
        #expect(knots.rates.map(\.value) == kmh.rates.map(\.value))
        #expect(knots.tally?.caption == kmh.tally?.caption)
    }

    // MARK: - What it costs

    /// **Why the document is built on open and not stored** (ADR-033, round 2, step 4).
    ///
    /// The session index already denormalizes the dozen numbers the library list needs; the
    /// document is the other ~40 KB, and the question was whether the phone should keep it
    /// beside the row. It should not, and this is the measurement: a build over the corpus's
    /// longest afternoon, in the same initializer that has just parsed a FIT and run
    /// `TrackCleaner` over it. A stored blob would need a migration, a staleness rule and a
    /// second answer to "which engine wrote this", and would buy back a millisecond.
    ///
    /// The ceiling is deliberately loose — a regression guard, not a benchmark — and the
    /// measured number is printed rather than asserted, because a loaded machine must not
    /// fail a suite over a timing.
    @Test func buildingTheDocumentIsCheapEnoughToDoOnOpen() throws {
        let analysis = try Self.analysis("2026-08-05-1356_nago-torbole-foilmotion_foilmotion")
        _ = PresentationDocument.build(analysis)          // warm

        let started = Date()
        let runs = 20
        for _ in 0..<runs { _ = PresentationDocument.build(analysis) }
        let each = Date().timeIntervalSince(started) / Double(runs)
        print("presentation document: \(String(format: "%.2f", each * 1000)) ms per build "
              + "(\(analysis.turns.count) turns, \(analysis.flightEnds.count) flight ends)")
        #expect(each < 0.1, "a document that takes 100 ms to build belongs in the database")
    }
}
