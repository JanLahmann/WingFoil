import Foundation

/// The period card's third artwork: every session's own small track, in a grid.
///
/// The stack (`TrackStack`) lays a period's afternoons on one another at one scale, which is
/// the right picture of a week at one beach and a scribble of a season at four. The collage
/// is the other answer (Jan, 28 Sep 2026): the period's best afternoons, each in a cell of
/// its own, fitted to itself, in the order they were ridden — a contact sheet of the season.
///
/// **Best** (`outranks`, `pick`, `best`) is most clean jibes, a tie going to the higher
/// best 2 s and then to the newer session; a session with no ladder at all ranks last. The
/// same ladder seeds "One session"'s default, in `PeriodShareView` and the twin of both in
/// web/js/sharecard.js (`collagePick` and the picker's default).
///
/// **The twin of `collageCells` in web/js/sharecard.js**, and of `collage_cells` in
/// web/tools/make_presentation_goldens.py, which writes the cases into
/// `fixtures/periods/outlines.expected.json` (`collage`). `TrackCollageTests` holds this to the
/// file, and `verify_presentation.py` §5e holds the browser to it.
public enum TrackCollage {

    /// At most this many cells. Twelve is a year of months or a fortnight of afternoons, and
    /// the cell a portrait card still gives a track at twelve is about a thumbnail's size.
    public static let limit = 12

    /// The gap between two cells, in layout points.
    public static let gap = 6.0

    /// Whether `a` outranks `b` on the period's ladder (Jan, 28 Sep 2026): more clean
    /// jibes wins; a tie goes to the higher best 2 s (a session with none ranks below one
    /// that has it); a tie there goes to whichever afternoon was ridden more recently.
    /// `pick` and `best` both read off this one comparison, so the collage and "One
    /// session"'s default can never disagree about which afternoon was best.
    static func outranks<T>(_ a: T, _ b: T, clean: (T) -> Int, best2s: (T) -> Double?,
                            start: (T) -> Date) -> Bool {
        let ca = clean(a), cb = clean(b)
        if ca != cb { return ca > cb }
        switch (best2s(a), best2s(b)) {
        case let (x?, y?) where x != y: return x > y
        case (nil, .some): return false
        case (.some, nil): return true
        default: break
        }
        return start(a) > start(b)
    }

    /// The period's best session by that same ladder — what "One session" seeds its choice
    /// with. `nil` only when `items` is empty.
    public static func best<T>(_ items: [T], clean: (T) -> Int, best2s: (T) -> Double?,
                               start: (T) -> Date) -> T? {
        items.reduce(into: nil as T?) { winner, item in
            if winner == nil || outranks(item, winner!, clean: clean, best2s: best2s,
                                         start: start) {
                winner = item
            }
        }
    }

    /// Which of a period's sessions the collage draws: the `limit` that rank best (Jan, 28
    /// Sep 2026 — most clean jibes, then the higher best 2 s, then the newest; a session
    /// with no ladder at all ranks last), still in the order they were ridden — a contact
    /// sheet stays chronological even when its frames were chosen for what they show.
    /// `items` is oldest first, as `Period.sessionIds` is, and the result keeps that order.
    public static func pick<T>(_ items: [T], clean: (T) -> Int, best2s: (T) -> Double?,
                               start: (T) -> Date) -> [T] {
        guard items.count > limit else { return items }
        let order = items.indices.sorted {
            outranks(items[$0], items[$1], clean: clean, best2s: best2s, start: start)
        }
        let kept = Set(order.prefix(limit))
        return items.indices.filter(kept.contains).map { items[$0] }
    }

    /// The cells for `count` tracks inside `box`, row by row.
    ///
    /// The column count is the one that gives a track the largest square — the smaller of a
    /// cell's two sides, which is what a fitted track is limited by — and ties go to fewer
    /// columns. A last row that is not full is centred, so a collage of five is two rows of
    /// three and two, not a hole in a corner.
    public static func cells(count: Int, in box: TrackStack.Box) -> [TrackStack.Box] {
        let n = min(count, limit)
        guard n > 0 else { return [] }
        func size(_ cols: Int) -> (w: Double, h: Double) {
            let rows = (n + cols - 1) / cols
            return ((box.w - gap * Double(cols - 1)) / Double(cols),
                    (box.h - gap * Double(rows - 1)) / Double(rows))
        }
        var cols = 1
        var bestSide = -Double.infinity
        for candidate in 1...n {
            let cell = size(candidate)
            let side = min(cell.w, cell.h)
            if side > bestSide + 1e-9 {
                bestSide = side
                cols = candidate
            }
        }
        let cell = size(cols)
        return (0..<n).map { i in
            let row = i / cols, col = i % cols
            let inRow = min(cols, n - row * cols)
            let offset = Double(cols - inRow) * (cell.w + gap) / 2
            return TrackStack.Box(x: box.x + offset + Double(col) * (cell.w + gap),
                                  y: box.y + Double(row) * (cell.h + gap),
                                  w: cell.w, h: cell.h)
        }
    }
}
