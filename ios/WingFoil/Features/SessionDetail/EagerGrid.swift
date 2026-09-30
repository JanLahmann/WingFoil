import SwiftUI

/// **A grid laid out in full — the session page's only kind** (Jan, 30 Sep 2026, dev 124:
/// "scroll in 124 does not work").
///
/// The session page is a bounded document: a few card blocks, one map, at most a hundred
/// turn rows. A `LazyVGrid` or `LazyVStack` inside it bought nothing and cost the scroll: a
/// lazy container that scrolled off the top forgets its cells, and when the thumb brings it
/// back from above it rebuilds them from an estimated height, measures the real one, and moves
/// the page's offset to make up the difference — under a finger that is pulling the other
/// way. On the Turns tab of a long session that was a 230–256 pt jump back on every pull, at
/// exactly the place where "Turns & losses" comes back into view, and the page could not get
/// past it (`LongTurnsScrollUITests`). This `Layout` measures every cell every time, so the
/// page's height never changes under a scroll.
///
/// It keeps `LazyVGrid`'s geometry for the two column kinds the page uses: `.adaptive` —
/// as many columns of at least `minimum` as fit, stretched to fill — and a fixed count of
/// equal flexible columns. Each cell is offered its column's width and sits in its row at
/// `alignment`, the way a grid item's alignment places it.
struct EagerGrid: Layout {
    enum Columns {
        case adaptive(minimum: CGFloat)
        case count(Int)
    }

    var columns: Columns
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat = 12
    var alignment: Alignment = .center

    private func columnCount(for width: CGFloat) -> Int {
        switch columns {
        case .count(let n):
            return max(1, n)
        case .adaptive(let minimum):
            guard width.isFinite, minimum > 0 else { return 1 }
            return max(1, Int(((width + spacing) / (minimum + spacing)).rounded(.down)))
        }
    }

    private struct Grid {
        var n: Int
        var columnWidth: CGFloat
        var sizes: [CGSize]
        var rowHeights: [CGFloat]
    }

    private func grid(_ width: CGFloat, _ subviews: Subviews) -> Grid {
        let n = columnCount(for: width)
        let columnWidth = max(0, (width - spacing * CGFloat(n - 1)) / CGFloat(n))
        let sizes = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
        }
        let rowHeights = stride(from: 0, to: sizes.count, by: n).map { start in
            sizes[start..<min(start + n, sizes.count)].map(\.height).max() ?? 0
        }
        return Grid(n: n, columnWidth: columnWidth, sizes: sizes, rowHeights: rowHeights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        if !width.isFinite {
            // Unconstrained: one row of ideal-size cells, as a grid would ask for.
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            return CGSize(width: sizes.map(\.width).reduce(0, +)
                              + spacing * CGFloat(max(0, sizes.count - 1)),
                          height: sizes.map(\.height).max() ?? 0)
        }
        let g = grid(width, subviews)
        let height = g.rowHeights.reduce(0, +) + rowSpacing * CGFloat(max(0, g.rowHeights.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        let g = grid(bounds.width, subviews)
        var y = bounds.minY
        for (row, rowHeight) in g.rowHeights.enumerated() {
            for column in 0..<g.n {
                let index = row * g.n + column
                guard index < subviews.count else { break }
                let size = g.sizes[index]
                let cellX = bounds.minX + CGFloat(column) * (g.columnWidth + spacing)
                let x: CGFloat
                switch alignment.horizontal {
                case .leading: x = cellX
                case .trailing: x = cellX + g.columnWidth - min(size.width, g.columnWidth)
                default: x = cellX + (g.columnWidth - min(size.width, g.columnWidth)) / 2
                }
                let top: CGFloat
                switch alignment.vertical {
                case .top: top = y
                case .bottom: top = y + rowHeight - size.height
                default: top = y + (rowHeight - size.height) / 2
                }
                subviews[index].place(at: CGPoint(x: x, y: top), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: g.columnWidth,
                                                                 height: size.height))
            }
            y += rowHeight + rowSpacing
        }
    }
}
