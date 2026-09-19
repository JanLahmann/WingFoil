import Foundation
import Testing
@testable import WingFoilKit

/// The direction a flick turns the page in, pinned to the platform's rule: the finger drags
/// the content, so leftwards brings in what comes next (Jan, Beta 75). A sign is read right
/// and written backwards, which is why it is a test rather than a flick on a phone.
@Suite struct SessionPagingTests {

    @Test func leftGoesToTheNextSession() {
        #expect(SessionPaging.step(dx: -140, dy: 4) == .next)
    }

    @Test func rightGoesBackToThePrevious() {
        #expect(SessionPaging.step(dx: 140, dy: -6) == .previous)
    }

    /// The two are mirror images at every distance that turns a page.
    @Test func theTwoDirectionsMirror() {
        for dx in stride(from: SessionPaging.commitDx, through: 400, by: 37) {
            #expect(SessionPaging.step(dx: -dx, dy: 0) == .next)
            #expect(SessionPaging.step(dx: dx, dy: 0) == .previous)
        }
    }

    /// Short of the commit distance and not thrown: the page stays where it is.
    @Test func aShortDragStays() {
        #expect(SessionPaging.step(dx: -60, dy: 2) == .stay)
    }

    /// A fast, short flick is a page turn — the same read a paged scroll view makes.
    @Test func aThrownFlickTurns() {
        #expect(SessionPaging.step(dx: -60, dy: 2, predictedDx: -260) == .next)
        #expect(SessionPaging.step(dx: 60, dy: 2, predictedDx: 260) == .previous)
    }

    /// A flick thrown back the way it came is not a page turn in either direction.
    @Test func aFlickThatReversesStays() {
        #expect(SessionPaging.step(dx: -60, dy: 2, predictedDx: 260) == .stay)
    }

    /// The inline map pans sideways too. A drag that is not much flatter than it is tall
    /// belongs to the map, at any length.
    @Test func aDiagonalDragBelongsToTheMap() {
        #expect(SessionPaging.step(dx: -100, dy: 45) == .stay)
        #expect(SessionPaging.isHorizontal(dx: -100, dy: 45) == false)
        #expect(SessionPaging.isHorizontal(dx: -160, dy: 10) == true)
        // Flat enough, and it turns the page: 160 is well past 2.5 × 40.
        #expect(SessionPaging.step(dx: -160, dy: 40) == .next)
    }

    /// And a scroll is not a page turn however far it runs.
    @Test func aVerticalDragStays() {
        #expect(SessionPaging.step(dx: -120, dy: 300) == .stay)
    }

    /// The page follows the finger the way it went, never further than the limit, and
    /// barely at all where there is nothing to turn to.
    @Test func thePageFollowsTheFinger() {
        #expect(SessionPaging.follow(dx: -120, hasTarget: true) < 0)
        #expect(SessionPaging.follow(dx: 120, hasTarget: true) > 0)
        #expect(abs(SessionPaging.follow(dx: 4000, hasTarget: true))
                <= SessionPaging.followLimit)
        #expect(abs(SessionPaging.follow(dx: 200, hasTarget: false))
                < abs(SessionPaging.follow(dx: 200, hasTarget: true)) / 2)
        #expect(SessionPaging.follow(dx: 0, hasTarget: true) == 0)
    }
}
