import Foundation
import Testing
@testable import WingFoilKit

/// The direction a flick turns the page in, pinned: time runs left to right, so the newer
/// session waits on the right and the finger, which drags the content, reaches it by
/// dragging left (Jan, 25 Sep 2026). A sign is read right and written backwards, which is
/// why it is a test rather than a flick on a phone.
@Suite struct SessionPagingTests {

    @Test func leftGoesToTheNewerSession() {
        #expect(SessionPaging.step(dx: -140, dy: 4) == .newer)
    }

    @Test func rightGoesBackToTheOlder() {
        #expect(SessionPaging.step(dx: 140, dy: -6) == .older)
    }

    /// The older page waits on the left, the newer on the right — the side the finger pulls
    /// it in from, and the side the header's ‹ › put it on.
    @Test func olderIsOnTheLeft() {
        #expect(SessionPaging.side(of: .older) < 0)
        #expect(SessionPaging.side(of: .newer) > 0)
        #expect(SessionPaging.side(of: .stay) == 0)
        // The page a drag is heading for is the one on the side it is pulling from.
        #expect(SessionPaging.heading(dx: -30) == .newer)
        #expect(SessionPaging.heading(dx: 30) == .older)
        #expect(SessionPaging.heading(dx: 0) == .stay)
    }

    /// The two are mirror images at every distance that turns a page.
    @Test func theTwoDirectionsMirror() {
        for dx in stride(from: SessionPaging.commitDx, through: 400, by: 37) {
            #expect(SessionPaging.step(dx: -dx, dy: 0) == .newer)
            #expect(SessionPaging.step(dx: dx, dy: 0) == .older)
        }
    }

    /// Short of the commit distance and not thrown: the page stays where it is.
    @Test func aShortDragStays() {
        #expect(SessionPaging.step(dx: -60, dy: 2) == .stay)
    }

    /// A fast, short flick is a page turn — the same read a paged scroll view makes.
    @Test func aThrownFlickTurns() {
        #expect(SessionPaging.step(dx: -60, dy: 2, predictedDx: -260) == .newer)
        #expect(SessionPaging.step(dx: 60, dy: 2, predictedDx: 260) == .older)
    }

    /// A flick thrown back the way it came is not a page turn in either direction.
    @Test func aFlickThatReversesStays() {
        #expect(SessionPaging.step(dx: -60, dy: 2, predictedDx: 260) == .stay)
    }

    /// A drag that is not much flatter than it is tall belongs to the scroll, at any length.
    @Test func aDiagonalDragBelongsToTheScroll() {
        #expect(SessionPaging.step(dx: -100, dy: 45) == .stay)
        #expect(SessionPaging.isHorizontal(dx: -100, dy: 45) == false)
        #expect(SessionPaging.isHorizontal(dx: -160, dy: 10) == true)
        // Flat enough, and it turns the page: 160 is well past 2.5 × 40.
        #expect(SessionPaging.step(dx: -160, dy: 40) == .newer)
    }

    /// And a scroll is not a page turn however far it runs.
    @Test func aVerticalDragStays() {
        #expect(SessionPaging.step(dx: -120, dy: 300) == .stay)
    }

    /// With a page to turn to, the page stays under the finger one to one — the lag of a
    /// rubber band from the first point was the "hakelig" feel. At the ends it barely moves.
    @Test func thePageFollowsTheFinger() {
        #expect(SessionPaging.follow(dx: -120, hasTarget: true) == -120)
        #expect(SessionPaging.follow(dx: 120, hasTarget: true) == 120)
        #expect(SessionPaging.follow(dx: 0, hasTarget: true) == 0)
        #expect(SessionPaging.follow(dx: 200, hasTarget: false) > 0)
        #expect(SessionPaging.follow(dx: -200, hasTarget: false) < 0)
        #expect(abs(SessionPaging.follow(dx: 4000, hasTarget: false))
                <= SessionPaging.deadEndLimit)
    }

    // MARK: - Neighbours

    private static let day: TimeInterval = 86_400
    private static let base = Date(timeIntervalSince1970: 1_780_000_000)

    /// Whatever order the list is grouped in, the pages lie oldest to newest.
    @Test func theTimelineRunsOldestFirst() {
        let items: [(id: String, start: Date)] = [
            ("wed", Self.base + 2 * Self.day),
            ("mon", Self.base),
            ("thu", Self.base + 3 * Self.day),
            ("tue", Self.base + Self.day),
        ]
        #expect(SessionPaging.timeline(items) == ["mon", "tue", "wed", "thu"])
    }

    /// Two sessions that started at the same instant keep the order they came in.
    @Test func tiesKeepTheirOrder() {
        let items: [(id: String, start: Date)] = [("b", Self.base), ("a", Self.base)]
        #expect(SessionPaging.timeline(items) == ["b", "a"])
    }

    @Test func neighboursAreEitherSide() {
        let timeline = ["mon", "tue", "wed"]
        let middle = SessionPaging.neighbours(of: "tue", in: timeline)
        #expect(middle.older == "mon")
        #expect(middle.newer == "wed")
        let first = SessionPaging.neighbours(of: "mon", in: timeline)
        #expect(first.older == nil)
        #expect(first.newer == "tue")
        let last = SessionPaging.neighbours(of: "wed", in: timeline)
        #expect(last.older == "tue")
        #expect(last.newer == nil)
        let stranger = SessionPaging.neighbours(of: "sun", in: timeline)
        #expect(stranger.older == nil && stranger.newer == nil)
    }
}
