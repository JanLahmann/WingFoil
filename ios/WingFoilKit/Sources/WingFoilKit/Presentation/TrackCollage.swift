import Foundation

/// The period card's third artwork: every session's own small track, in a grid.
///
/// The stack (`TrackStack`) lays a period's afternoons on one another at one scale, which is
/// the right picture of a week at one beach and a scribble of a season at four. The collage
/// is the other answer (Jan, 28 Sep 2026): each afternoon in a cell of its own, fitted to
/// itself, in the order they were ridden — a contact sheet of the season.
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

    /// Which of a period's sessions the collage draws: the newest `limit`, still in the order
    /// they were ridden. `ids` is oldest first, as `Period.sessionIds` is.
    public static func pick<T>(_ ids: [T]) -> [T] {
        Array(ids.suffix(limit))
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
        var best = -Double.infinity
        for candidate in 1...n {
            let cell = size(candidate)
            let side = min(cell.w, cell.h)
            if side > best + 1e-9 {
                best = side
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
