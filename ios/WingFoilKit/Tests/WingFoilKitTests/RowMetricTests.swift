import Foundation
import Testing
@testable import WingFoilKit

/// The three numbers a library row carries: every one of them has a word, the default three
/// are the ones the list opens with, and the rider's choice survives being written down
/// (Jan, Beta 75 — "review meaning of numbers and the icons, maybe make configurable").
@Suite struct RowMetricTests {

    func row() -> SessionRow {
        var row = SessionRow(id: "s1", startDate: Date(timeIntervalSince1970: 1_700_000_000),
                             durationS: 5_400, sourceClass: "b")
        row.foilPct = 37.4
        row.flightCount = 13
        row.jibes = 24
        row.jibesSuccessful = 9
        row.turnsCounted = 31
        row.best2sKn = 13.254
        row.best10sKn = 12.1
        row.distanceKm = 21.06
        row.longestDryStreak = 7
        row.rateDurationS = 5_400
        return row
    }

    /// Pattern H, as a test: no metric may reach a row without the word that says what it
    /// is, or without the glyph it is scanned by.
    @Test func everyMetricHasAWordAndAGlyph() {
        for metric in RowMetric.allCases {
            #expect(!metric.label.isEmpty)
            #expect(!metric.icon.isEmpty)
            // A label is a word, not a sentence: it sits under a number in caption type.
            #expect(metric.label.split(separator: " ").count <= 3)
            #expect(metric.label == metric.label.lowercased())
        }
    }

    /// Each glyph means its word (Jan, 25 September 2026): clean wears the clean jibe's own
    /// star in its own ink, foil is not a standing figure, and turns is not the sync arrows.
    @Test func theGlyphsMeanTheirWords() {
        #expect(RowMetric.cleanJibes.icon == DesignTokens.Glyph.cleanJibe)
        #expect(RowMetric.allCases.filter(\.wearsCleanInk) == [.cleanJibes])
        #expect(RowMetric.foilShare.icon == "water.waves.and.arrow.up")
        #expect(HelpSection.foil.symbol == RowMetric.foilShare.icon)
        #expect(!RowMetric.allCases.map(\.icon).contains("arrow.triangle.2.circlepath"))
        // Only the two speed windows share a glyph; everything else is told apart by shape.
        let icons = RowMetric.allCases.filter { $0 != .best10s }.map(\.icon)
        #expect(Set(icons).count == icons.count)
    }

    /// Two metrics sharing a word would make the picker unanswerable.
    @Test func theWordsAreDistinct() {
        let labels = Set(RowMetric.allCases.map(\.label))
        #expect(labels.count == RowMetric.allCases.count)
    }

    /// How much he flew, how many jibes, how fast — and the middle cell is the jibes the
    /// glyph always looked like, never the flight count it used to draw.
    @Test func theDefaultTriple() {
        #expect(RowMetric.defaultTriple == [.foilShare, .jibes, .best2s])
        #expect(RowMetric.defaultTriple.count == RowMetric.slots)
    }

    @Test func everyMetricSpellsItsValue() {
        let row = row()
        #expect(RowMetric.foilShare.format(row) == "37 %")
        #expect(RowMetric.flights.format(row) == "13")
        #expect(RowMetric.jibes.format(row) == "24")
        #expect(RowMetric.cleanJibes.format(row) == "9")
        #expect(RowMetric.turns.format(row) == "31")
        #expect(RowMetric.best2s.format(row) == "13.25 kn")
        #expect(RowMetric.best10s.format(row) == "12.10 kn")
        #expect(RowMetric.distance.format(row) == "21.1 km")
        #expect(RowMetric.duration.format(row) == "1:30 h")
        #expect(RowMetric.dryStreak.format(row) == "7")
    }

    /// A row the engine has not read yet reports an absence, never a zero.
    @Test func anEmptyRowPrintsDashes() {
        let empty = SessionRow(id: "s2", startDate: Date(), durationS: 0, sourceClass: "b")
        for metric in RowMetric.allCases where metric != .duration {
            #expect(metric.format(empty) == "—")
        }
    }

    @Test func theChoiceRoundTrips() {
        let chosen: [RowMetric] = [.duration, .cleanJibes, .best10s]
        #expect(RowMetric.triple(stored: RowMetric.stored(chosen)) == chosen)
    }

    /// Nothing written down yet is the default, and so is anything unreadable — a metric a
    /// later build dropped, or half a value. Never a row one cell short.
    @Test func anUnreadableChoiceFallsBack() {
        #expect(RowMetric.triple(stored: nil) == RowMetric.defaultTriple)
        #expect(RowMetric.triple(stored: "") == RowMetric.defaultTriple)
        #expect(RowMetric.triple(stored: "duration") == [.duration, .jibes, .best2s])
        #expect(RowMetric.triple(stored: "duration,windAngle,best10s")
                == [.duration, .jibes, .best10s])
        #expect(RowMetric.triple(stored: "a,b,c,d,e").count == RowMetric.slots)
    }
}

/// The map behind a row's track is a picture of the square the outline is drawn in, widened
/// to the tile's own shape. Both halves used to be guessed separately, and the map came out
/// at a different scale from the line on top of it (Jan, Beta 75).
@Suite struct TrackTileRegionTests {

    @Test func theRegionMatchesTheTilesShape() throws {
        let extent = TrackTileRegion.extent(spanM: 340, width: 62, height: 44, inset: 5)
        let tile = try #require(extent)
        // The drawn square is the shorter side less both insets: 44 - 10 = 34 points.
        #expect(abs(tile.metresPerPoint - 10) < 0.0001)
        #expect(abs(tile.widthM - 620) < 0.0001)
        #expect(abs(tile.heightM - 440) < 0.0001)
        #expect(abs(tile.aspect - 62.0 / 44.0) < 0.0001)
    }

    /// The square carries the whole track, so the region is never smaller than the session.
    @Test func theRegionHoldsTheWholeTrack() throws {
        let tile = try #require(TrackTileRegion.extent(spanM: 900, width: 62, height: 44,
                                                       inset: 5))
        #expect(tile.widthM >= 900)
        #expect(tile.heightM >= 900)
    }

    /// An inset that eats the tile leaves no square to be a picture of.
    @Test func anImpossibleTileHasNoRegion() {
        #expect(TrackTileRegion.extent(spanM: 340, width: 62, height: 44, inset: 25) == nil)
        #expect(TrackTileRegion.extent(spanM: 0, width: 62, height: 44, inset: 5) == nil)
    }
}
