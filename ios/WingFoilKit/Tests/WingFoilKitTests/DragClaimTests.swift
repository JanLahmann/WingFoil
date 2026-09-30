import Foundation
import Testing
@testable import WingFoilKit

/// The strips' finger rule, pinned (Jan, 28 Sep 2026: the turn page stuck on a thumb
/// that leaned sideways before it scrolled).
@Suite struct DragClaimTests {

    @Test func aShortMoveIsNotACallYet() {
        #expect(DragClaim.decide(dx: 12, dy: 4) == .undecided)
        #expect(DragClaim.decide(dx: 0, dy: 0) == .undecided)
        #expect(DragClaim.decide(dx: -14, dy: 13) == .undecided)
    }

    @Test func aFlatDragGoesSidewaysEitherWay() {
        #expect(DragClaim.decide(dx: 30, dy: 3) == .sideways)
        #expect(DragClaim.decide(dx: -30, dy: -8) == .sideways)
        #expect(DragClaim.decide(dx: 24, dy: 0) == .sideways)
    }

    @Test func anUpOrDownDragScrollsEitherWay() {
        #expect(DragClaim.decide(dx: 0, dy: 24) == .upDown)
        #expect(DragClaim.decide(dx: 3, dy: -30) == .upDown)
    }

    /// The thumb that stuck: 14 points sideways in its first 12, then straight down. At
    /// the platform's ten points it read as a scrub; at twenty it is a scroll.
    @Test func aThumbThatLeansSidewaysFirstStillScrolls() {
        #expect(DragClaim.decide(dx: 14, dy: 15) == .upDown)
        #expect(DragClaim.decide(dx: -14, dy: -16) == .upDown)
    }

    /// A 45° drag went sideways under the old rule; it is the page's now.
    @Test func aDiagonalBelongsToThePage() {
        #expect(DragClaim.decide(dx: 20, dy: 20) == .upDown)
        #expect(DragClaim.decide(dx: 25, dy: 18) == .upDown)
        #expect(DragClaim.decide(dx: 27, dy: 18) == .sideways)
    }
}
