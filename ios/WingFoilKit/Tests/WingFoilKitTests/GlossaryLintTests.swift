import Foundation
import Testing
@testable import WingFoilKit

/// **Every rider-facing metric label is a glossary term.**
///
/// Jan, 20 September 2026: *"the definitions of the numbers are important to clarify, make
/// transparent, and consistent across all surfaces."* The case behind it was a tester who
/// compared three screens about one afternoon and read *Turn success 29 %* in Garmin
/// Connect, *93 % flew through* on the site and 44 % on the phone. All three were right.
/// Nothing said they were three different measurements, and nothing could have: the two
/// that collided were spelled in two files that never met.
///
/// So this is the meeting place. A label a rider reads is a term in `MetricGlossary` or it
/// is a pure unit, a clock, a distance or a place — the allow-list below, one reason each.
/// A new label that is neither fails here, which is one commit earlier than it would have
/// reached a screen (docs/review-checklist.md, pattern L: one taxonomy per concept).
@Suite struct GlossaryLintTests {

    // MARK: - The allow-list

    /// **What a metric label may be without being a glossary term.**
    ///
    /// Units, clocks and plain measures — the words that mean the same on every screen in
    /// every product and carry no CleanJibe definition — plus the maneuver nouns, which are
    /// the rider's own lexicon (`docs/copy/phrases.json`) rather than metrics. Each entry
    /// says why. An allow-list that is not read becomes the rule, so it is printed by the
    /// failure message of every test below.
    static let allowed: [String: String] = [
        "duration": "a clock. Every product spells it the same and CleanJibe adds nothing",
        "time": "the same clock, at a row's width",
        "distance": "a plain measure, in km",
        "avg speed": "a plain measure. The window it averages is the session itself",
        "longest flight": "a clock over the flights term, not a second metric",
        "jibes": "a maneuver noun from the rider lexicon, not a metric",
        "tacks": "a maneuver noun from the rider lexicon, not a metric",
        "turns": "a maneuver noun from the rider lexicon, not a metric",
        "unclassified turns": "the maneuver noun with the state that named it",
        "port / starboard": "the entry side, a dimension of a turn rather than a metric",
        "glide-outs": "a flight-end verdict that is not a loss and has no other surface",
        "touchdowns": "the plural of the touchdown term",
        "best streaks": "the dry-streak term at the block's width",
        "pumps to takeoff": "a stroke count, under the takeoffs term",
        "takeoff run": "a clock, under the takeoffs term",
        "pump strokes": "a stroke count",
        "failed attempts": "the attempts term's complement, spelled on the same card",
        "run to planing": "the windsurf lexicon's spelling of the takeoff run",
        "heart rate": "a sensor reading, not a CleanJibe verdict",
    ]

    static func isKnown(_ label: String) -> Bool {
        let want = label.lowercased().trimmingCharacters(in: .whitespaces)
        return MetricGlossary.allLabels.contains(want) || allowed[want] != nil
    }

    static func complaint(_ label: String, _ where_: String) -> String {
        """
        "\(label)" is printed by \(where_) and is not a glossary term.

        Add it to `MetricGlossary` — as a term of its own, or as a `labels` spelling of the
        term it already is — or, if it is a pure unit, a clock or a maneuver noun, add it to
        GlossaryLintTests.allowed with the reason. The allow-list today:
        \(allowed.keys.sorted().map { "  · \($0) — \(allowed[$0]!)" }.joined(separator: "\n"))
        """
    }

    // MARK: - The typed surfaces

    /// The library row's cells, which are the rider's own choice of three.
    @Test func everyRowMetricLabelIsAGlossaryTerm() {
        for metric in RowMetric.allCases {
            #expect(Self.isKnown(metric.label),
                    Comment(rawValue: Self.complaint(metric.label, "RowMetric.\(metric.rawValue)")))
        }
    }

    /// The key-metrics block, built from a real session's numbers so every branch that can
    /// print a cell prints one: the tally, the streaks, the falls and all four rates.
    @Test func everyKeyMetricLabelIsAGlossaryTerm() {
        for block in [Self.block(jibes: 50), Self.block(jibes: 0)] {
            let labels = block.basics.map(\.label) + [block.maxSpeed.label]
                + block.speedExtras.map(\.label)
                + [block.streaks?.label, block.falls?.label].compactMap { $0 }
                + block.rates.map(\.label)
            for label in labels {
                #expect(Self.isKnown(label),
                        Comment(rawValue: Self.complaint(label, "the key-metrics block")))
            }
        }
    }

    /// The share card is the block re-laid-out, so its labels are the block's plus the
    /// tally's and the outro's own cell. It is checked separately because it is the one
    /// artefact that leaves the device.
    @Test func everyShareCardLabelIsAGlossaryTerm() {
        let stats = ShareCardStats.stats(from: Self.block(jibes: 50), preset: .complete)
            + [ShareCardStats.longestFlightStat(424)].compactMap { $0 }
        for stat in stats {
            #expect(Self.isKnown(stat.label),
                    Comment(rawValue: Self.complaint(stat.label, "the share card")))
        }
    }

    /// The divergence banner names a metric per row, and a rider reads those names beside
    /// the watch's own (docs/presentation.md, "The divergence banner").
    @Test func everyDivergenceMetricNameIsAGlossaryTerm() {
        for name in Self.divergenceNames {
            #expect(Self.isKnown(name),
                    Comment(rawValue: Self.complaint(name, "the divergence banner")))
        }
    }

    /// Every name `DivergenceCheck.compare` can put in a row. Listed rather than provoked:
    /// building a watch summary that trips all eleven thresholds is a fixture, not a lint,
    /// and `theBannerNamesNothingElse` below holds the list to the source.
    static let divergenceNames = [
        "Foil time", "Best 2 s", "Best 10 s", "Best 5×10 s", "Best 500 m", "Best 1 NM",
        "Alpha 500", "Flights", "Tacks", "Jibes", "Takeoff attempts", "Takeoffs",
    ]

    /// …and the list above is the source's, not a copy that can drift: every `"…"` the
    /// banner uses as a metric name is in it.
    @Test func theBannerNamesNothingElse() throws {
        let file = CopyContractTests.repoRoot
            .appendingPathComponent("ios/WingFoilKit/Sources/WingFoilKit/AnalysisEngine")
            .appendingPathComponent("DivergenceCheck.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let found = Self.quoted(text, after: #"\(\s*""#)
        for name in found {
            #expect(Self.divergenceNames.contains(name),
                    """
                    DivergenceCheck names "\(name)" and GlossaryLintTests.divergenceNames \
                    does not list it. Add it there, and to the glossary or the allow-list.
                    """)
        }
    }

    // MARK: - The scanned surfaces

    /// **The session page's stat cards**, which are where most of the app's numbers are
    /// actually read, and which are written in the app target where no type can enumerate
    /// them. So they are scanned: every `StatCard(title: "…")` in `SummaryGrid.swift`.
    @Test func everyStatCardTitleIsAGlossaryTerm() throws {
        let file = CopyContractTests.repoRoot
            .appendingPathComponent("ios/WingFoil/Features/SessionDetail/SummaryGrid.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let titles = Self.quoted(text, after: #"StatCard\(title: ""#)
        #expect(titles.count >= 8, "the scan found \(titles.count) stat cards — check the pattern")
        for title in titles {
            #expect(Self.isKnown(title),
                    Comment(rawValue: Self.complaint(title, "a session-page stat card")))
        }
    }

    // MARK: - The glossary's own shape

    /// Ids are unique, and no two terms claim the same spelling — the second would make
    /// the lint's answer depend on the order of the list.
    @Test func noTwoTermsClaimTheSameLabel() {
        var owner: [String: String] = [:]
        for entry in MetricGlossary.entries {
            for label in entry.labels + [entry.term] {
                let key = label.lowercased()
                if let first = owner[key], first != entry.id {
                    Issue.record("\"\(label)\" is claimed by both \(first) and \(entry.id)")
                }
                owner[key] = entry.id
            }
        }
    }

    /// Every entry says where it shows, and a term that names a FIT field says which one.
    /// The pair is what the help topic prints and what a rider comparing two screens is
    /// pointed at.
    @Test func everyTermSaysWhereItShows() {
        for entry in MetricGlossary.entries {
            #expect(!entry.places.isEmpty, "\(entry.id) shows nowhere")
            #expect(!MetricGlossary.places(entry).isEmpty, "\(entry.id) has no places line")
            if entry.places.contains(.fitField) {
                #expect(!entry.fit.isEmpty,
                        "\(entry.id) claims a FIT field and does not name it")
            }
            if entry.places.contains(.connectField) {
                #expect(entry.places.contains(.fitField),
                        "\(entry.id) is a Garmin Connect row without a FIT field behind it")
            }
        }
    }

    /// **The three collisions of 20 September 2026, pinned.** Each of the three numbers a
    /// tester compared has its own word now, and none of them is the engine's.
    @Test func theThreeCollidingNumbersHaveThreeWords() {
        let speed = MetricGlossary.entry("speedKept")
        let flew = MetricGlossary.entry("flewThrough")
        let up = MetricGlossary.entry("takeoffs")
        #expect(speed.term != flew.term && flew.term != up.term && speed.term != up.term)
        #expect(speed.fit == "turn_success_pct",
                "the FIT field the watch writes the speed verdict into moved")
        for entry in [speed, flew, up] {
            let words = (entry.labels + [entry.term, entry.line]).joined(separator: " ")
                .lowercased()
            #expect(!words.contains("success"),
                    "\(entry.id) says \"success\", which is engine vocabulary (CLAUDE.md)")
            #expect(!words.contains("carried"),
                    "\(entry.id) says \"carried\", which is engine vocabulary (CLAUDE.md)")
        }
    }

    // MARK: - Helpers

    /// The 29 Aug Torbole numbers, the same ones `PresentationTests` eyeballs the block
    /// against — with a flight-end block, so the falls cell exists.
    static func block(jibes: Int) -> KeyMetrics {
        var summary = SessionSummary(foilTimeS: 3780, foilPct: 53.8, flightCount: 31,
                                     longestFlightS: 424, maxFlightM: 1580,
                                     distanceKm: 22.985)
        summary.apply(SessionRates(durationS: 7029, timerTimeS: 7029, distanceM: 22_985,
                                   dryTurns: 51, dryJibes: 43, fellIn: 25, cleanJibes: 12))
        summary.turns.turnsCounted = 51
        summary.turns.jibes = jibes
        summary.turns.jibesSuccessful = 12
        summary.turns.turnsSuccessful = 12
        summary.turns.longestDryStreak = 11
        summary.turns.longestFlewStreak = 5
        summary.flightEnds.all.fellIn = 25
        summary.flightEnds.all.touchdown = 6
        summary.flightEnds.inTurn.fellIn = 4
        summary.flightEnds.straight.fellIn = 21
        var records = GP3SRecords()
        records.best2sKn = 13.209
        records.best10sKn = 12.1
        records.best5x10sKn = 11.9
        records.alpha500Kn = 10.2
        return KeyMetrics.make(summary: summary, records: records)
    }

    /// Every string literal that follows `pattern` in `text`. Deliberately crude: it is a
    /// lint over one file with one shape in it, and a parser would be a second engine.
    static func quoted(_ text: String, after pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern + #"([^"\\]*)""#) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
