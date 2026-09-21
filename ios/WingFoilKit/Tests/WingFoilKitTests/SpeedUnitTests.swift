import Foundation
import Testing
@testable import WingFoilKit

/// **One unit function, and every speed on the phone goes through it.**
///
/// Jan, 20 September 2026, relaying a user's request from a shared card: *speed unit
/// configurable, km/h besides knots*. The browser app had the switch already; the phone had
/// knots typed into nine formatters and five chart axes, which is a setting that works on
/// eight screens and lies on the ninth.
///
/// The engine is untouched by any of this and the tests below say so: records stay in
/// knots, goldens stay in knots, and the conversion happens on the way to a string.
@Suite struct SpeedUnitTests {

    @Test func knotsIsTheDefaultAndTheRecordsStayInIt() {
        #expect(SpeedUnitStore.load(from: Self.emptyDefaults()) == .knots)
        #expect(Speed.unit == .knots)
        #expect(Speed.format(13.209) == "13.21 kn")
    }

    @Test func kilometresPerHourConvertsTheStringAndNothingElse() {
        Speed.$override.withValue(.kmh) {
            #expect(Speed.format(13.209) == "24.46 km/h")
            #expect(Speed.suffix == "km/h")
            #expect(abs(Speed.value(10) - 18.52) < 1e-9)
        }
        // Outside the block the platform is back in knots: the conversion is a rendering,
        // not a state the analysis can end up in.
        #expect(Speed.format(13.209) == "13.21 kn")
    }

    @Test func anAbsentSpeedIsAnEmDashInEitherUnit() {
        #expect(Speed.format(nil) == "—")
        Speed.$override.withValue(.kmh) { #expect(Speed.format(nil) == "—") }
    }

    /// **The surfaces, one assertion each.** Every one of them printed `%.2f kn` of its own
    /// until 20 September 2026.
    @Test func everySurfaceFollowsTheSetting() {
        var row = SessionRow(id: "x", startDate: Date(), durationS: 3600,
                             sourceClass: "a")
        row.best2sKn = 13.209
        row.wetExits = 3
        let block = GlossaryLintTests.block(jibes: 50)
        let card = ShareCardStats.stats(from: block, preset: .complete)

        Speed.$override.withValue(.kmh) {
            #expect(KeyMetrics.knots(13.209) == "24.46 km/h")
            #expect(RowMetric.best2s.format(row) == "24.46 km/h")
            #expect(TurnCoach.kn(13.2) == "24.4 km/h")
            #expect(KeyMetrics.make(summary: Self.summary(), records: Self.records())
                        .maxSpeed.value.hasSuffix("km/h"))
            #expect(ShareCardStats.stats(from: GlossaryLintTests.block(jibes: 50),
                                         preset: .complete)
                        .first { $0.key == ShareCardStats.Key.maxSpeed }?
                        .value.hasSuffix("km/h") == true)
        }
        // …and the same list in knots, so a failure says which half moved.
        #expect(RowMetric.best2s.format(row) == "13.21 kn")
        #expect(card.first { $0.key == ShareCardStats.Key.maxSpeed }?.value == "13.21 kn")
        #expect(block.maxSpeed.value == "13.21 kn")
    }

    /// **No second formatter, on any surface.** A unit spelled into a rider-facing string is
    /// a screen that will keep saying knots after the rider has asked for km/h — the exact
    /// defect the setting exists to remove, and the one a fenix 5X Plus rider still found on
    /// 21 September 2026: *"Metric only, no knots in any part of the Phone App."* Four chart
    /// axes, five narrated sentences, the records margin, the widgets and the watch app were
    /// all printing knots under a setting that said km/h.
    ///
    /// So the scan is the whole iOS tree — the app, the kit, both widget extensions and the
    /// watch app — and it reads **string literals**, not lines, so a `knots(` call or a
    /// `bestKn` property is not an offence and a `"%.2f kn"` inside a comment-free line is.
    /// Everything still allowed to spell a unit is in `exempt` with the reason it is there.
    @Test func noSurfaceSpellsTheUnitItself() throws {
        var offenders: [String] = []
        for dir in Self.scanned {
            let root = CopyContractTests.repoRoot.appendingPathComponent(dir)
            let files = FileManager.default.enumerator(at: root,
                                                       includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" } ?? []
            for file in files.sorted(by: { $0.path < $1.path }) {
                let relative = file.path
                    .replacingOccurrences(of: CopyContractTests.repoRoot.path + "/", with: "")
                if Self.exempt.keys.contains(where: { relative.hasPrefix($0) }) { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                for literal in Self.literals(in: text) where Self.spellsAUnit(literal) {
                    offenders.append(relative + ": \"" + literal + "\"")
                }
            }
        }
        #expect(offenders.isEmpty,
                """
                a speed unit is spelled outside the one formatter:
                \(offenders.joined(separator: "\n"))

                Print it with `Speed.format` / `Speed.suffix` (kit and app), \
                `WidgetFormat.knots` (widgets) or `WatchFormat.speed` (the watch app) — \
                or add the file to SpeedUnitTests.exempt with the reason it may say it. \
                The exemptions today:
                \(Self.exempt.keys.sorted()
                    .map { "  · \($0) — \(Self.exempt[$0]!)" }
                    .joined(separator: "\n"))
                """)
    }

    /// Where the scan runs: **everything on iOS a rider can read.**
    static let scanned = [
        "ios/WingFoilKit/Sources/WingFoilKit",
        "ios/WingFoil",
        "ios/WingFoilWidgets",
        "ios/WingFoilWatch",
        "ios/WingFoilWatchWidgets",
        "ios/WatchShared",
    ]

    /// **Who may spell a unit, and why.** Three kinds, and nothing else:
    ///
    /// 1. **The formatters.** `SpeedUnit` is the platform's; the widget extension and the
    ///    watch app link none of the kit (project.yml says why) so each carries the kit's
    ///    rule in one documented mirror, named in the failure message above.
    /// 2. **Prose about the setting.** Help, the settings footer, the what's-new list and
    ///    the getting-started guide *teach* the two words — a sentence explaining that
    ///    Settings → Units switches knots to km/h has to be able to say "knots" and "km/h".
    ///    None of them prints a measured speed.
    /// 3. **The dev workbench and the tuning sheet**, which read the engine in the engine's
    ///    own units on purpose (docs/presentation.md, "The dev workbench") — a threshold in
    ///    km/h is the number in `TuningOverrides`, not a reading off the water.
    static let exempt: [String: String] = [
        "ios/WingFoilKit/Sources/WingFoilKit/Presentation/SpeedUnit.swift":
            "the unit itself lives here",
        "ios/WingFoilWidgets/WidgetChrome.swift":
            "the widget's documented mirror of the kit's formatter (ADR-011: no kit link)",
        "ios/WingFoilWatch/Views/WatchFormat.swift":
            "the watch app's documented mirror of the kit's formatter (no kit link)",
        "ios/WingFoilKit/Sources/WingFoilKit/Presentation/Dev":
            "the dev workbench reads the engine in the engine's units on purpose",
        "ios/WingFoil/Features/SessionDetail/Dev":
            "the dev workbench reads the engine in the engine's units on purpose",
        "ios/WingFoilKit/Sources/WingFoilKit/AnalysisEngine/TuningOverrides.swift":
            "a tuning parameter's own unit, which is the engine's and not a reading",
        "ios/WingFoilKit/Sources/WingFoilKit/Help":
            "help prose teaches the setting, and has to be able to name both units",
        "ios/WingFoilKit/Sources/WingFoilKit/Presentation/SettingsCopy.swift":
            "the Units section's own footer, which names what the picker switches between",
    ]

    /// **The lint has teeth**, which a lint that scans a clean tree cannot otherwise show.
    /// A planted `kn` is found, a comment about knots is not code, and neither a property
    /// name nor an ordinary English word is an offence.
    @Test func theScanReadsLiteralsAndNotIdentifiers() {
        #expect(Self.literals(in: "let s = \"13.47 kn\" // knots live here")
                == ["13.47 kn"])
        #expect(Self.spellsAUnit("13.47 kn"))
        #expect(Self.spellsAUnit("kn"))
        #expect(Self.spellsAUnit("%.1f knots coming in"))
        #expect(Self.spellsAUnit("24.94 km/h"))
        #expect(!Self.spellsAUnit("best2sKn"))
        #expect(!Self.spellsAUnit("alpha500Kn"))
        #expect(!Self.spellsAUnit("knee"))
        #expect(!Self.spellsAUnit("Best 2 s"))
        // An interpolated call is the formatter doing its job, not a typed-out unit.
        #expect(!Self.spellsAUnit("\\(label) \\(Fmt.kn(value, digits: 1))"))
    }

    // MARK: - The scanner

    /// Every double-quoted literal in a Swift source, with comments removed first so a
    /// quotation inside `//` prose is not read as code.
    ///
    /// Deliberately small: it tracks three states (code, string, comment) and nothing else.
    /// A string containing an escaped quote ends up split in two, which can only produce a
    /// *smaller* literal to test and never a missed unit.
    static func literals(in source: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inString = false
        var inLineComment = false
        var inBlockComment = false
        var previous: Character = " "
        for character in source {
            if inLineComment {
                if character == "\n" { inLineComment = false }
                previous = character
                continue
            }
            if inBlockComment {
                if previous == "*", character == "/" { inBlockComment = false }
                previous = character
                continue
            }
            if inString {
                if character == "\"", previous != "\\" {
                    inString = false
                    out.append(current)
                    current = ""
                } else {
                    current.append(character)
                }
                previous = character
                continue
            }
            if previous == "/", character == "/" { inLineComment = true; previous = character
                continue }
            if previous == "/", character == "*" { inBlockComment = true; previous = character
                continue }
            if character == "\"" { inString = true; current = "" }
            previous = character
        }
        return out
    }

    /// A literal with its interpolations removed — `"\(label) \(Fmt.kn(v))"` becomes
    /// `" "`. What a call *returns* is the formatter's business and is checked by the tests
    /// above; only the words the source types out are this scan's business.
    static func withoutInterpolations(_ literal: String) -> String {
        var out = ""
        var depth = 0
        var previous: Character = " "
        var index = literal.startIndex
        while index < literal.endIndex {
            let character = literal[index]
            if depth == 0, previous == "\\", character == "(" {
                out.removeLast()          // the backslash already appended
                depth = 1
            } else if depth > 0 {
                if character == "(" { depth += 1 }
                if character == ")" { depth -= 1 }
            } else {
                out.append(character)
            }
            previous = character
            index = literal.index(after: index)
        }
        return out
    }

    /// Whether a literal names a speed unit: `km/h` anywhere, the word `knot`, or a bare
    /// `kn` standing on its own (`"kn"`, `"%.2f kn"`, `"13.47 kn"`) rather than inside a
    /// word like `knee` or an identifier like `alpha500Kn`.
    static func spellsAUnit(_ literal: String) -> Bool {
        let lower = withoutInterpolations(literal).lowercased()
        if lower.contains("km/h") || lower.contains("knot") { return true }
        let characters = Array(lower)
        guard characters.count >= 2 else { return false }
        for index in 0...(characters.count - 2)
        where characters[index] == "k" && characters[index + 1] == "n" {
            let before = index > 0 ? characters[index - 1] : " "
            let after = index + 2 < characters.count ? characters[index + 2] : " "
            // `alpha500Kn` is a column name, not a caption: a digit in front of the two
            // letters makes them the tail of an identifier rather than a word of English.
            if !before.isLetter, !before.isNumber, !after.isLetter, !after.isNumber {
                return true
            }
        }
        return false
    }

    // MARK: - Helpers

    static func emptyDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "speedUnitTests." + UUID().uuidString)!
        suite.removeObject(forKey: SpeedUnitStore.defaultsKey)
        return suite
    }

    static func summary() -> SessionSummary {
        SessionSummary(foilTimeS: 100, foilPct: 10, flightCount: 1, longestFlightS: 100,
                       maxFlightM: 100, distanceKm: 1)
    }

    static func records() -> GP3SRecords {
        var r = GP3SRecords()
        r.best2sKn = 13.209
        return r
    }
}
