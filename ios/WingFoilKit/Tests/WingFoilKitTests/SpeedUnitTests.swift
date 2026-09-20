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

    /// **No second formatter.** A `kn` literal in a rider-facing string is a screen that
    /// will keep saying knots after the rider has asked for km/h, which is the exact defect
    /// this setting exists to remove. The two exemptions below are written down rather than
    /// silently skipped, and each is a surface the round left in knots on purpose.
    @Test func noSurfaceSpellsTheUnitItself() throws {
        var offenders: [String] = []
        for dir in Self.scanned {
            let root = CopyContractTests.repoRoot.appendingPathComponent(dir)
            let files = FileManager.default.enumerator(at: root,
                                                       includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" } ?? []
            for file in files {
                let relative = file.path
                    .replacingOccurrences(of: CopyContractTests.repoRoot.path + "/", with: "")
                if Self.exempt.keys.contains(where: { relative.hasPrefix($0) }) { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    let code = line.trimmingCharacters(in: .whitespaces)
                    guard !code.hasPrefix("//"), !code.hasPrefix("///") else { continue }
                    guard code.contains("\" kn\"") || code.contains(" kn\"")
                            || code.contains("\"kn\"") else { continue }
                    offenders.append(relative + ": " + code)
                }
            }
        }
        #expect(offenders.isEmpty,
                """
                a speed unit is spelled outside `Speed`:
                \(offenders.joined(separator: "\n"))

                Print it with `Speed.format` / `Fmt.kn`, or add the file to \
                SpeedUnitTests.exempt with the reason it stays in knots.
                """)
    }

    /// Where the scan runs.
    static let scanned = [
        "ios/WingFoilKit/Sources/WingFoilKit/Presentation",
        "ios/WingFoil/Features",
    ]

    /// **What is still knots, and why.** Both are surfaces that plot rather than print: the
    /// value on the axis is the number the chart is drawn from, so converting the label
    /// without the series would be worse than either. They move in the round that converts
    /// the chart domains (docs/presentation.md, "Units").
    static let exempt: [String: String] = [
        "ios/WingFoilKit/Sources/WingFoilKit/Presentation/SpeedUnit.swift":
            "the unit itself lives here",
        "ios/WingFoilKit/Sources/WingFoilKit/Presentation/Dev":
            "the dev workbench reads the engine in the engine's units on purpose",
        "ios/WingFoil/Features/SessionDetail/SpeedChartView.swift":
            "a chart axis: the series is plotted in knots",
        "ios/WingFoil/Features/SessionDetail/TurnDetailStripView.swift":
            "a chart axis: the series is plotted in knots",
        "ios/WingFoil/Features/SessionDetail/FlightEndDetailView.swift":
            "a chart axis: the series is plotted in knots",
        "ios/WingFoil/Features/Trends/TrendsView.swift":
            "a chart axis: the series is plotted in knots",
    ]

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
