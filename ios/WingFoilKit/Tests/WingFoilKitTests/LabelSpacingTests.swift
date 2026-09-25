import Foundation
import Testing
@testable import WingFoilKit

/// Captions on a strip step up a row rather than print over each other, and an axis keeps
/// the ticks that matter most when the rest would smear (Jan, 25 Sep 2026: "5" and
/// "out 5.7" merged, and 18 / 5 / −5 / −18 overprinted on the rate axis).
@Suite struct LabelSpacingTests {

    @Test func farApartCaptionsShareTheFirstRow() {
        #expect(LabelSpacing.rows([-2, 1.5, 5], gap: 1.5) == [0, 0, 0])
    }

    /// "low" and "out" a second apart: "out" steps up, it never goes under the plot.
    @Test func aCloseCaptionStepsUp() {
        #expect(LabelSpacing.rows([-2, 4.6, 5.2], gap: 1.5) == [0, 0, 1])
    }

    /// Three on one instant climb three rows; a fourth elsewhere goes back to the first.
    @Test func captionsClimbAsFarAsTheyHaveTo() {
        #expect(LabelSpacing.rows([0, 0.2, 0.4, 6], gap: 1.5) == [0, 1, 2, 0])
    }

    /// A caption fills the lowest free row, not the one above the last it saw.
    @Test func aCaptionTakesTheLowestFreeRow() {
        // "out" collides with "low" and goes up to row 1; "axis" collides with "low" on
        // row 0 and with "out" on row 1, so it takes row 2.
        #expect(LabelSpacing.rows([-3, 2, 2.5, 2.2], gap: 1.5) == [0, 0, 1, 2])
    }

    @Test func ticksKeepTheirPriority() {
        // A ±60 °/s axis, 14 °/s the least two labels may sit apart: the continue
        // thresholds at ±5 give way to zero, the peak ones at ±18 stay.
        let kept = LabelSpacing.thinned([0, 18, -18, 5, -5], gap: 14)
        #expect(kept == [0, 18, -18])
    }

    @Test func ticksWithRoomAllStay() {
        #expect(LabelSpacing.thinned([0, 18, -18, 5, -5], gap: 4) == [0, 18, -18, 5, -5])
    }
}
