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
        #expect(tally.label == "flew · touch · fell")
        #expect(tally.caption == "of 18 jibes")
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

        #expect(block.rates.map(\.key) == ["cph", "jph", "wph"])
        #expect(block.rates.map(\.label) == ["CPH · clean jibes per hour",
                                             "JPH · dry jibes per hour",
                                             "WPH · swims per hour"])
        #expect(block.rates.map(\.value) == ["0.0", "5.4", "6.6"])
    }

    /// **The card is the block, minus the two composites.** It was the document's own rule
    /// before it was a renderer's, and `card.tiles` *are* `block` cells by construction —
    /// so this asserts that the Swift card and the document's card agree on which keys
    /// survive, on every fixture rather than on one.
    /// **Layout B v2 is the shared fixture** (26 Sep 2026): for every corpus document and
    /// every hero, the kit's story is the browser's, word for word and count for count.
    /// `fixtures/cards/stories.expected.json` is dumped by web/tools/card_parity.mjs and
    /// held by verify_presentation.py §5a; this holds `ShareCardStats.Story.make` to it.
    @Test func theCardStoryIsTheSharedFixture() throws {
        let url = testFixturesDir.appendingPathComponent("cards/stories.expected.json")
        let fixture = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)) as? [String: [String: Any]])
        var checked = 0
        for (stem, document) in try Self.everyDocument() {
            let want = try #require(fixture[stem], "\(stem): not in the story fixture")
            let metrics = KeyMetrics.make(block: document["block"] ?? .null)
            for hero in ShareCardStats.Hero.allCases {
                let story = ShareCardStats.Story.make(metrics: metrics,
                                                      maxSpeed: metrics.maxSpeed,
                                                      hero: hero, dateLine: "",
                                                      speedNote: nil)
                let got = Self.json(story)
                let expected = try #require(want[hero.rawValue] as? [String: Any])
                #expect(NSDictionary(dictionary: got).isEqual(to: expected),
                        "\(stem)/\(hero.rawValue): the kit's story is not the fixture's\n\(got)")
                checked += 1
            }
        }
        #expect(checked >= 3 * 18)
    }

    /// A story as the JSON card_parity.mjs dumps.
    static func json(_ story: ShareCardStats.Story) -> [String: Any] {
        let hero: Any = story.hero.map {
            ["kind": $0.kind.rawValue, "value": $0.value, "unit": $0.unit, "sub": $0.sub]
        } ?? NSNull()
        let segments = { (s: [ShareCardStats.Story.Segment]) in
            s.map { ["text": $0.text, "role": $0.role] }
        }
        return [
            "dateLine": story.dateLine,
            "hero": hero,
            "heroOptions": story.heroOptions.map(\.rawValue),
            "bars": story.bars.map { bar -> [String: Any] in
                ["kind": bar.kind, "label": bar.label, "flewThrough": bar.flewThrough,
                 "touchdown": bar.touchdown, "fellIn": bar.fellIn,
                 "right": bar.right.map { $0 as Any } ?? NSNull(), "star": bar.star]
            },
            "streak": segments(story.streak),
            "falls": segments(story.falls),
            "ribbon": story.ribbon.map {
                ["key": $0.key, "label": $0.label, "value": $0.value, "clean": $0.clean]
            },
            "speedNote": story.speedNote.map { $0 as Any } ?? NSNull(),
            "legend": story.legend,
        ]
    }

    /// With 0 clean jibes the clean number is left out, and the hero falls back to the speed.
    @Test func zeroCleanJibesLeaveTheCleanNumberOut() throws {
        let metrics = KeyMetrics.make(
            block: try Self.document("2026-07-31-1451_nago-torbole-windsurfen_native")["block"]
                ?? .null)
        let story = ShareCardStats.Story.make(metrics: metrics, maxSpeed: metrics.maxSpeed,
                                              hero: .clean, dateLine: "",
                                              speedNote: ShareCardStats.speedEstimated)
        #expect(story.hero?.kind == .max2s)
        #expect(!story.heroOptions.contains(.clean))
        #expect(story.bars.first?.right == "of 23 jibes")
        #expect(!story.ribbon.contains { $0.key == "cph" })
        #expect(story.speedNote == "speed estimated from GPS positions")
        // No speed on the card (records policy), no note and no speed hero.
        let bare = ShareCardStats.Story.make(metrics: metrics, maxSpeed: nil, hero: .max2s,
                                             dateLine: "", speedNote: "x")
        #expect(bare.hero == nil)
        #expect(bare.speedNote == nil)
    }

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

    // MARK: - (c) the records table and its windows

    /// **The table's nine rows, and which of them are live.**
    ///
    /// `SessionRecordsTable` drew `RecordWindowSelection.catalogue` and asked
    /// `kind.value(in:)` and `records.windows[key]` per row; it walks `records.kinds` now.
    /// The three things that decide what a rider sees are asserted against the fixture's
    /// own `recordWindows` list, which is what the web verifier has always compared to:
    /// the catalogue order, the locatable set, and the default the session opens on.
    @Test func theRecordsTableIsTheDocumentsNineKinds() throws {
        for (stem, document) in try Self.everyDocument() {
            let records = try #require(document["records"])
            let kinds = try #require(records["kinds"]?.arrayValue)
            #expect(kinds.compactMap { $0["key"]?.stringValue }
                    == RecordKind.allCases.map(\.rawValue),
                    "\(stem): the table's rows are not the catalogue, in its order")

            // Every row names itself out of `tokens.recordWindow.<id>`, which is
            // `RecordKind.label` — one spelling per record, everywhere one is named.
            for kind in kinds {
                let label = PresentationCopy.text(kind["labelId"]?.stringValue ?? "")
                #expect(label == RecordKind(rawValue: kind["key"]?.stringValue ?? "")?.label,
                        "\(stem): a record row is not calling the record by its name")
            }

            // A row is live exactly when the document says the session achieved it: a
            // value **and** a window. A record with neither is inert and says nothing.
            let achieved = Set((records["achieved"]?.arrayValue ?? []).compactMap(\.stringValue))
            let live = Set(kinds.compactMap { kind -> String? in
                guard case .bool(true)? = kind["achieved"] else { return nil }
                return kind["key"]?.stringValue
            })
            #expect(live == achieved, "\(stem): achieved and the live rows disagree")
            #expect(RecordWindowSelection.initial(available: achieved)
                    == records["default"]?.stringValue,
                    "\(stem): the table would open on a different record than the document")
        }
    }

    /// **5×10 s is its five runs.** The one record made of several windows, which the
    /// `GP3SRecords` subscript only ever yielded the top of — the map glows on all five,
    /// and the table's caption names the first, which is the same run it always named.
    @Test func theCompositeRecordKeepsAllOfItsWindows() throws {
        var sawFive = false
        for (stem, document) in try Self.everyDocument() {
            let analysis = try Self.analysis(stem)
            for kind in document["records"]?["kinds"]?.arrayValue ?? []
            where kind["key"]?.stringValue == "best5x10s" {
                let windows = kind["windows"]?.arrayValue ?? []
                let engine = analysis.records.windows.best5x10s ?? []
                #expect(windows.count == engine.count, "\(stem): 5×10 s lost a run")
                if windows.count > 1 { sawFive = true }
                // The caption's run is `best5x10s?.first`, unsorted — the same one the
                // table printed before it read the document.
                if let first = windows.first, let top = engine.first {
                    #expect(first["startTs"] == PresentationDocument.number(top.startTs,
                                                                           "seconds"),
                            "\(stem): the caption would name a different run")
                }
            }
        }
        #expect(sawFive, "no fixture carried a multi-window 5×10 s record")
    }

    // MARK: - (d) the strip, the marks and the callouts

    /// **The map's marks are the document's strip and its drawn ends.**
    ///
    /// `buildMarkers` asked `PresentationRules` for a tone and `FlightEndAnalytics` for the
    /// drawn set; it reads `turns.strip[].colourRole` and `flightEnds.marks` now. The
    /// counts that come out of those two lists are the ones every fixture has pinned since
    /// the corpus existed, so this is the assertion that the renderer's input and the
    /// verifier's expectation are one thing.
    @Test func theMarksOnTheMapAreTheDocumentsOwn() throws {
        for (stem, document) in try Self.everyDocument() {
            let expected = try Self.expectations(stem)
            let markers = try #require(expected["markers"] as? [String: Int])

            // The two channels the map draws, together — a solid dot per sweep and a hollow
            // ring per drawn flight end — because that is what `buildMarkers` produces and
            // what `markers` has always counted (docs/algorithms/pumping.md, ownership).
            var byTone: [String: Int] = [:]
            for entry in (document["turns"]?["strip"]?.arrayValue ?? [])
                + (document["flightEnds"]?["marks"]?.arrayValue ?? []) {
                byTone[entry["colourRole"]?.stringValue ?? "", default: 0] += 1
            }
            #expect(byTone["outcome.flew"] ?? 0 == markers["flewThrough"], "\(stem): flew-through marks")
            #expect(byTone["outcome.touchdown"] ?? 0 == markers["touchdown"], "\(stem): touchdown marks")
            #expect(byTone["outcome.fellIn"] ?? 0 == markers["fellIn"], "\(stem): fell-in marks")
            #expect(byTone["outcome.courseChange"] ?? 0 == markers["courseChange"], "\(stem): course-change marks")

            // The star lies *across* the ladder: a clean jibe answers to the clean chip and
            // to its outcome chip, which is why it is a flag on the entry and not a rung.
            let clean = (document["turns"]?["strip"]?.arrayValue ?? [])
                .filter { $0["clean"] == .bool(true) }
            #expect(clean.count == expected["cleanJibes"] as? Int, "\(stem): clean jibes")
            #expect(clean.allSatisfy { $0["layerId"]?.stringValue == MapLayer.cleanJibe.rawValue },
                    "\(stem): a clean jibe is not answering to the clean chip")

            // The hollow rings: exactly the drawn ends, no fewer and none twice.
            let ends = try #require(expected["flightEnds"] as? [String: Int])
            let drawn = document["flightEnds"]?["marks"]?.arrayValue ?? []
            #expect(drawn.count == ends["drawn"], "\(stem): the hollow rings are miscounted")
            let indices = drawn.compactMap { mark -> Int? in
                if case .int(let i)? = mark["index"] { return i }
                return nil
            }
            #expect(Set(indices).count == drawn.count, "\(stem): a flight end drawn twice")
            // …and the same indices, in the same order, that `FlightEndAnalytics` handed
            // the Log tab's list and its detail sheet before they read the document. Three
            // readers of one rule became one list.
            #expect(indices == FlightEndAnalytics.drawnIndices(try Self.analysis(stem)),
                    "\(stem): the flight-end list is not the drawn ends, in order")
        }
    }

    /// **"Wrist under · 4 s", "during jibe 7", "after flight 12 ended, stopped 3 s".**
    ///
    /// The sharpest case of the whole round: the same sentence was spelled in Swift, in
    /// `web/js` and a third time in the verifier that existed to stop the first two
    /// drifting. It is one copy id with arguments now, and this renders every episode of
    /// every fixture through the resolver the phone calls — a callout that came out empty,
    /// or with a `{placeholder}` still in it, is a sentence with no home.
    @Test func everyWristUnderCalloutRendersFromTheDocument() throws {
        var episodes = 0
        for (stem, document) in try Self.everyDocument() {
            let splash = try #require(document["splash"])
            let expected = try Self.expectations(stem)
            #expect(splash["episodes"] == .int(expected["splash"] as? Int ?? -1),
                    "\(stem): submersion episodes")

            for mark in splash["marks"]?.arrayValue ?? [] {
                episodes += 1
                let title = try #require(mark["title"].flatMap(PresentationCopy.captionText),
                                         "\(stem): a wrist-under title has no home")
                let during = try #require(mark["during"].flatMap(PresentationCopy.captionText),
                                          "\(stem): a wrist-under clause has no home")
                #expect(title.hasPrefix("Wrist under"), "\(stem): \(title)")
                #expect(!title.contains("{") && !during.contains("{"),
                        "\(stem): an argument was never interpolated — \(title) / \(during)")
                #expect(!during.isEmpty)
            }
        }
        #expect(episodes > 0, "no fixture carried a submersion episode")
    }

    /// The three shapes the `during` clause has, built here because the corpus does not
    /// produce all three — the same three the lab pins in
    /// `test_the_branches_no_corpus_fixture_is`, rendered rather than named.
    @Test func theThreeWristUnderClausesReadAsEnglish() {
        func during(_ id: String, _ args: [String: PresentationValue]) -> String? {
            PresentationCopy.captionText(id, args: args)
        }
        #expect(during("presentation.wristUnder.duringTurn",
                       ["turnId": .string("jibe"), "ordinal": .int(7)]) == "during jibe 7")
        #expect(during("presentation.wristUnder.duringAnyTurn",
                       ["turnId": .string("bearAway")]) == "during a bear-away")
        #expect(during("presentation.wristUnder.afterFlightStopped",
                       ["flight": .int(12), "stoppedS": .number(3)])
                == "after flight 12 ended, stopped 3 s")
        #expect(during("presentation.wristUnder.afterFlight", ["flight": .int(12)])
                == "after flight 12 ended")
        #expect(during("presentation.wristUnder.offFoil", [:]) == "while off foil")
        #expect(during("presentation.wristUnder.titleFor", ["durationS": .number(4)])
                == "Wrist under · 4 s")
    }

    /// The fixture's own expectations — the counts `web/tools/verify_presentation.py` has
    /// compared both platforms against since before the document existed.
    static func expectations(_ stem: String) throws -> [String: Any] {
        let url = testFixturesDir
            .appendingPathComponent("presentation/\(stem).expected.json")
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try #require(parsed as? [String: Any], "\(stem): not a JSON object")
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
