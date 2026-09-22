import Foundation
import Testing
@testable import WingFoilKit

/// The Trends page's per-session series, held to the analyzer's own answer.
///
/// `fixtures/periods/periods.expected.json` carries ten synthetic afternoons **and** —
/// since the three rates moved onto one page together — every trend chart
/// `web/lab_bundle/library.py` makes of them: the charts in order, their units, every
/// point, and which of the speed points a recording could certify. This suite builds the
/// same library out of the `sessions` half and reads the phone's own numbers back through
/// `LibraryStore.trend`.
///
/// It is the same argument `PeriodTests` makes, one screen along: two platforms drawing
/// "the same" chart is worth nothing unless one of them is the reference and the other is
/// checked against it. Python is the reference (docs/presentation/trends-periods.md, "Trend charts").
///
/// The three charts with no point in them are as load-bearing as the seven with points:
/// this fixture carries no turn outcomes, no per-side split and no pump tally, so both
/// platforms have to answer **absent** — never a flattering zero — for all ten sessions.
@Suite struct TrendSeriesTests {

    /// Every line key the fixture can hold, and where the phone keeps that number.
    ///
    /// Written out rather than derived, because this map *is* the claim: "the analyzer's
    /// `cph` line and the phone's `cleanJibesPerHour` are one metric". A line the analyzer
    /// adds without a twin here fails `everyAnalyzerLineHasATwin` below rather than being
    /// quietly skipped.
    static let value: [String: @Sendable (TrendPoint) -> Double?] = [
        "foilPct": { $0.foilPct },
        "longestFlightS": { $0.longestFlightS },
        "flewThroughPct": { $0.flewThroughPct },
        "cleanJibes": { $0.cleanJibes.map(Double.init) },
        "cph": { $0.cleanJibesPerHour },
        "jph": { $0.jibesPerHour },
        "tph": { $0.turnsPerHour },
        "best2sKn": { $0.best2sKn },
        "avgPumpsToTakeoff": { $0.avgPumpsToTakeoff },
        "port": { $0.portFlewThroughPct },
        "starboard": { $0.starboardFlewThroughPct },
    ]

    /// The analyzer rounds every point to three decimals before it publishes it; so does
    /// this, or a rate that agrees to the digit fails on the twelfth one.
    static func rounded(_ value: Double?) -> Double? {
        value.map { ($0 * 1000).rounded() / 1000 }
    }

    @Test func everyAnalyzerLineHasATwin() throws {
        let charts = try PeriodTests.loadFixture().trends.charts
        for chart in charts {
            for line in chart.lines {
                #expect(Self.value[line.key] != nil,
                        "no phone-side twin for \(chart.key)/\(line.key)")
            }
        }
    }

    @Test func trendSeriesMatchTheAnalyzer() async throws {
        let fixture = try PeriodTests.loadFixture()
        let store = try await PeriodTests.library(fixture)
        let points = try await store.trend()
        // Oldest first on both sides, and the same ten afternoons in the same order — a
        // series that agreed value for value on a different ordering would agree about
        // nothing.
        let ids = fixture.trends.charts.first?.lines.first?.points.map(\.id) ?? []
        #expect(points.map(\.sessionId) == ids)

        for chart in fixture.trends.charts {
            for line in chart.lines {
                guard let read = Self.value[line.key] else { continue }
                let got = points.map { Self.rounded(read($0)) }
                let want = line.points.map { Self.rounded($0.v) }
                #expect(got == want, "\(chart.key)/\(line.key)")
            }
        }
    }

    /// The three rates are one row of the page, not one metric with two optional extras:
    /// CPH says he rode the jibe, JPH says he got away with it, TPH says how busy the
    /// afternoon was (docs/algorithms/rates.md, "Session rates"). All three come off the engine,
    /// and the two new ones have **no** fallback — a row the v17 sweep has not reached has
    /// a gap in those two lines rather than a number nothing published.
    @Test func theThreeRatesAreDrawnTogether() async throws {
        let fixture = try PeriodTests.loadFixture()
        let keys = fixture.trends.charts.map(\.key)
        #expect(keys.contains("cph") && keys.contains("jph") && keys.contains("tph"))
        let units = Dictionary(uniqueKeysWithValues: fixture.trends.charts.map {
            ($0.key, $0.unit)
        })
        #expect(units["cph"] == "clean jibes / h")
        #expect(units["jph"] == "jibes / h")
        #expect(units["tph"] == "turns / h")

        let points = try await PeriodTests.library(fixture).trend()
        let a6 = try #require(points.first { $0.sessionId == "a6" })
        #expect(a6.jibesPerHour == nil)
        #expect(a6.turnsPerHour == nil)
        #expect(a6.cleanJibesPerHour != nil)      // CPH still divides for an old row
    }

    /// The one speed series, and the one chart whose points say whether the recording could
    /// certify them. Knots on both platforms, and every point says what its recording was —
    /// `certified` is a fact about the file, not about the setting, so the class-(c)
    /// afternoon carries `false` whether or not its value is drawn.
    @Test func theBest2sSeriesIsKnotsAndKnowsWhatItCannotCertify() async throws {
        let fixture = try PeriodTests.loadFixture()
        let chart = try #require(fixture.trends.charts.first { $0.key == "best2s" })
        #expect(chart.unit == "kn")
        #expect(chart.label == "Best 2 s")

        let points = try await PeriodTests.library(fixture).trend()
        let byId = Dictionary(uniqueKeysWithValues: points.map { ($0.sessionId, $0) })
        for point in chart.lines[0].points {
            let mine = try #require(byId[point.id])
            #expect(mine.certified == (point.certified ?? true), "\(point.id)")
        }
        #expect(byId["c2"]?.certified == false)
        #expect(byId["a1"]?.certified == true)
    }

    /// **Settings → Speed records reaches this line too** (22 September 2026). The library
    /// holds nine verified afternoons and one class-(c) one, so under the default
    /// `preferVerified` the unverified point has nothing to fill: it keeps its column and
    /// loses its value, exactly as `library._points(certify=True)` leaves it — which is why
    /// the fixture's own chart no longer carries the uncertified badge.
    @Test func theBest2sSeriesFollowsTheSpeedRecordPolicy() async throws {
        let fixture = try PeriodTests.loadFixture()
        let chart = try #require(fixture.trends.charts.first { $0.key == "best2s" })
        #expect(!chart.uncertified)
        let store = try await PeriodTests.library(fixture)

        let preferred = try await store.trend()
        let dropped = try #require(preferred.first { $0.sessionId == "c2" })
        #expect(dropped.best2sKn == nil)
        #expect(dropped.certified == false)                 // the mark is about the file
        #expect(preferred.count == fixture.sessions.count)  // the column stayed
        #expect(preferred.first { $0.sessionId == "a1" }?.best2sKn != nil)

        // The rider who wants every record drawn gets the point back, value and mark.
        let all = try await store.trend(policy: .includeUnverified)
        let kept = try #require(all.first { $0.sessionId == "c2" })
        #expect(kept.best2sKn == 11.5)
        #expect(kept.certified == false)

        // Only verified answers like prefer verified here, and would differ only on a
        // library with no verified best 2 s at all.
        let strict = try await store.trend(policy: .onlyVerified)
        #expect(strict.first { $0.sessionId == "c2" }?.best2sKn == nil)
        #expect(strict.first { $0.sessionId == "a1" }?.best2sKn != nil)
    }

    /// The other side of `preferVerified`: a library whose **only** best 2 s is unverified
    /// still draws it, marked, because there is no verified effort for it to lose to.
    @Test func anUnverifiedOnlyLibraryStillDrawsItsBest2s() async throws {
        let fixture = try PeriodTests.loadFixture()
        let store = try await PeriodTests.library(fixture)
        try await store.database.writer.write { db in
            try db.execute(sql: "UPDATE session SET best2sKn = NULL WHERE id <> 'c2'")
        }
        let points = try await store.trend()
        #expect(points.first { $0.sessionId == "c2" }?.best2sKn == 11.5)
        // And under Only verified that same library has no speed line at all.
        let strict = try await store.trend(policy: .onlyVerified)
        #expect(strict.allSatisfy { $0.best2sKn == nil })
    }
}
