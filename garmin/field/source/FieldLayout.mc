import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Layout maths for a data field, which — unlike the device app's own views — has no idea in
// advance how big its canvas is: the user drops it into a 1-, 2-, 3- or 4-field page and the
// system hands us whatever rectangle is left. Everything here is static and Dc-driven so the
// unit tests can measure the real device fonts and prove nothing clips, on any cell size.
//
// Four rules keep it readable on the water:
//   1. rows are stacked from dc.getFontHeight() only, so they can never overlap;
//   2. every row picks the LARGEST font that still fits its own width budget — and where the
//      cell reaches the rim of a round display that budget is the chord of the circle at the
//      row's deepest edge, not the bounding box, because a round display has no corners;
//   3. a stack in a cell against the rim leans away from it, into the spare room at the other
//      end, before it gives up a font size — the pixels above a top-anchored stack are empty
//      and the pixels beside a bottom-anchored one are missing, so the trade is free;
//   4. a cell that still cannot hold a layout's widest row does not get that layout: it steps
//      down a rung, because two numbers you can read beat three you cannot.
//
// Rules 2-4 used to apply only to the 1-field page, on the reasoning that a partial cell is a
// rectangle carved out of the middle of the glass and can use its full width. That is true of
// the middle of a stack and false at either end of it — the bottom half of a 2-field page IS
// the bottom of the circle — and the turn row lost its first and last characters to the bezel
// on every layout with a cell against the rim. The system will say which edges those are
// (WatchUi.DataField.getObscurityFlags(), valid inside onUpdate); place() turns that answer
// into the geometry the chord needs.
module FieldLayout {
    enum {
        SIZE_SMALL = 0,     // 3- or 4-field cell: 2 numbers, nothing else
        SIZE_WIDE = 1,      // 2-field cell (or a wide 3-field row): 3 rows
        SIZE_FULL = 2       // 1-field page: the rich grid
    }

    // Pixels of bezel/edge margin kept clear on every side.
    const MARGIN = 4;

    // How many times fitRows() re-measures a stack after a row has changed size. See the
    // pass-2 comment there: shrinking a row moves the whole stack, so one round can be
    // optimistic. Every real cell settles in two.
    const REFITS = 3;

    // WatchUi.DataField.OBSCURE_*, mirrored so the layout maths — and the suite that drives it
    // with the real cell rectangles of all twelve layouts — never needs a DataField instance.
    // The values have been these four bits since CIQ 1.0.
    const EDGE_LEFT = 1;
    const EDGE_TOP = 2;
    const EDGE_RIGHT = 4;
    const EDGE_BOTTOM = 8;

    // Largest-first font ladders. fitFont() walks them and takes the first that fits.
    const NUM_FONTS = [Graphics.FONT_NUMBER_THAI_HOT, Graphics.FONT_NUMBER_HOT,
        Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD, Graphics.FONT_LARGE,
        Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY,
        Graphics.FONT_XTINY] as Array<Graphics.FontType>;
    const TEXT_FONTS = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL,
        Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontType>;

    // The widest string every row of every layout will ever show, indexed by SIZE_*, with the
    // ladder each of those rows walks. The fit is worst-case against these, so the display
    // cannot start clipping later in the session when the counts get bigger — and one table
    // means the drawing code, the size gate and the layout suite can never disagree about what
    // the worst case is. They did: the suite used to fit the WIDE turn row against
    // "TOUCH 100%", eight characters shorter than the "TOUCH 100% · 99/99" the field draws
    // there, which is most of the reason a clipped turn row got past it.
    var WIDEST as Array<Array<String> > = [
        ["100%", "99 · 88:88"],
        ["100%", "99 · 88:88", "TOUCH 100% · 99/99"],
        ["88.8 km/h", "100%", "99 · 88:88", "TOUCH 100%", "99/99 · 99·99·99"]
    ];
    var LADDERS as Array<Array> = [
        [NUM_FONTS, TEXT_FONTS],
        [NUM_FONTS, TEXT_FONTS, TEXT_FONTS],
        [TEXT_FONTS, NUM_FONTS, TEXT_FONTS, TEXT_FONTS, TEXT_FONTS]
    ];

    // Where a cell sits on a round glass, and therefore how much of each row the missing
    // corners eat. Built once per onUpdate from the cell rectangle and the obscurity flags;
    // null whenever there is nothing to correct for (see place()).
    class Glass {
        var y0 as Number;       // the cell's top edge, in SCREEN pixels
        var cx as Float;        // the GLASS's centre, in this cell's coordinates
        var cy as Float;        // the glass's centre, in screen coordinates
        var r as Float;         // the radius ink may use
        var lean as Number;     // +1: cell against the top rim, so a stack leans DOWN; -1: up

        function initialize(x0 as Number, top as Number, screenW as Number,
                screenH as Number, way as Number) {
            y0 = top;
            cx = screenW / 2.0 - x0;
            cy = screenH / 2.0;
            r = screenW / 2.0 - MARGIN;
            lean = way;
        }
    }

    // The cell's place on the glass, from the edges the system says are obscured.
    //
    // Horizontally the flags always answer: every cell Garmin lays out runs to the left rim,
    // the right rim, or both. Vertically they answer only at the ends of the stack, which is
    // where the answer matters — a band that touches neither rim was carved out of the middle
    // of the glass, where the chord is at its widest and the bounding box is the binding
    // constraint. Its offset is genuinely unknowable from in here (in a 5-field stack the
    // fourth band is nowhere near the centre, so "assume centred" would be a lie that reads as
    // maths), so such a cell gets no correction and keeps its full rectangle.
    function place(w as Number, h as Number, screenW as Number, screenH as Number,
            flags as Number, round as Boolean) as Glass? {
        if (!round) {
            return null;        // square glass: the rectangle is the truth
        }
        var top = (flags & EDGE_TOP) != 0;
        var bottom = (flags & EDGE_BOTTOM) != 0;
        if (!top && !bottom) {
            return null;
        }
        var x0 = 0;
        if ((flags & EDGE_LEFT) == 0 && (flags & EDGE_RIGHT) != 0) {
            x0 = screenW - w;
        }
        // A cell against ONE rim has a free edge to lean away towards. A cell against both is
        // the whole glass and has nowhere to go.
        var way = 0;
        if (top != bottom) {
            way = top ? 1 : -1;
        }
        return new Glass(x0, top ? 0 : screenH - h, screenW, screenH, way);
    }

    // Which layout a cell of this size gets. Thresholds are fractions of the device screen, so
    // one rule covers 416/454 AMOLED and 260/280 MIP fenix 8 variants. This is the room
    // question only; fitCell() asks the one that decides.
    function classify(w as Number, h as Number, screenW as Number,
            screenH as Number) as Number {
        if (h * 100 >= screenH * 60 && w * 100 >= screenW * 80) {
            return SIZE_FULL;           // a 1-field page: essentially the whole glass
        }
        if (h * 100 >= screenH * 30) {
            return SIZE_WIDE;           // half the screen: a 2-field page
        }
        return SIZE_SMALL;
    }

    // The layout this cell can actually CARRY, and the stack that carries it:
    // [size, fonts, lean].
    //
    // classify() measures the room in fractions of the glass and is height-only above
    // SIZE_SMALL, which is how a 225 px quadrant of a 454 px watch — half the screen tall, and
    // half the screen WIDE — came to be handed the three-row layout whose turn row wants
    // 289 px at FONT_XTINY, the smallest font there is. This asks the question that decides:
    // laid out for real, with the lean and the ladder both spent, does every row still fit the
    // width the glass gives it? If not the cell steps down a rung, because two numbers you can
    // read beat three you cannot.
    function fitCell(dc as Graphics.Dc, w as Number, h as Number, screenW as Number,
            screenH as Number, g as Glass?) as Array {
        var size = classify(w, h, screenW, screenH);
        var stack = fitStack(dc, w, h, WIDEST[size], LADDERS[size], g);
        while (size > SIZE_SMALL && !stackFits(dc, w, h, WIDEST[size], stack, g)) {
            size--;
            stack = fitStack(dc, w, h, WIDEST[size], LADDERS[size], g);
        }
        return [size, stack[0], stack[1]] as Array;
    }

    // Fonts and lean for one set of rows in one cell: [fonts, lean].
    //
    // The centred stack is tried first and kept unless leaning away from the rim buys a bigger
    // font somewhere, so a cell that was never in trouble is left exactly where it always was.
    function fitStack(dc as Graphics.Dc, w as Number, h as Number, texts as Array<String>,
            ladders as Array, g as Glass?) as Array {
        var fonts = fitRows(dc, w, h, texts, ladders, g, 0);
        if (g == null || g.lean == 0) {
            return [fonts, 0] as Array;
        }
        var leaned = fitRows(dc, w, h, texts, ladders, g, g.lean);
        if (stackInk(dc, leaned) > stackInk(dc, fonts)) {
            return [leaned, g.lean] as Array;
        }
        return [fonts, 0] as Array;
    }

    // How much glyph a set of fonts is worth. Bigger is better, and a tie keeps the centred
    // stack — that is what makes the lean invisible everywhere it is not needed.
    function stackInk(dc as Graphics.Dc, fonts as Array<Graphics.FontType>) as Number {
        var total = 0;
        for (var i = 0; i < fonts.size(); i++) {
            total += dc.getFontHeight(fonts[i]);
        }
        return total;
    }

    // Does this stack's worst case survive in this cell, once fitStack has spent everything it
    // has? fitRows() has already stepped every row down to the smallest font in its ladder if
    // that is what it took, so a row that still overflows here overflows at any size.
    function stackFits(dc as Graphics.Dc, w as Number, h as Number, texts as Array<String>,
            stack as Array, g as Glass?) as Boolean {
        var fonts = stack[0] as Array<Graphics.FontType>;
        var lean = stack[1] as Number;
        var heights = heightsOf(dc, fonts);
        for (var i = 0; i < texts.size(); i++) {
            var y = stackY(h, heights, i, lean);
            if (y - heights[i] / 2 < 0 || y + heights[i] / 2 > h) {
                return false;       // the stack does not even fit the cell's height
            }
            if (dc.getTextWidthInPixels(texts[i], fonts[i])
                    > rowWindow(w, y, heights[i], g)[1]) {
                return false;
            }
        }
        return true;
    }

    // The horizontal window a row of height rowH centred at cell-local y actually has, in CELL
    // coordinates: [centre, width]. It is the cell's own box intersected with the chord of the
    // glass at the row's deepest edge — the same geometry the device app's Turns-page test
    // asserts, applied ahead of time instead of after the fact.
    //
    // The centre is part of the answer because a corner cell is not centred on the glass: the
    // chord runs out on the inboard side of such a cell long before the outboard one, and a
    // row glued to the middle of its own cell loses characters at one end that it could have
    // kept by sliding towards the middle of the WATCH.
    //
    // When the two do not overlap at all the model has run out — the row's font BOX has left
    // the glass even though its ink has not, which happens in the 78 px top band of a 7-field
    // page — and the answer is the one the field gave before any of this existed: a width of
    // zero (so the ladder walks to its smallest font) at the centre of the cell.
    //
    // Note the whole font box is budgeted, not the ink inside it, which is a few pixels either
    // side of pessimistic. That is the pessimism the 1-field page has always been fitted with,
    // and one rule for every cell is worth more here than the odd recovered pixel.
    function rowWindow(w as Number, y as Number, rowH as Number, g as Glass?) as Array<Number> {
        var lo = MARGIN.toFloat();
        var hi = (w - MARGIN).toFloat();
        if (g != null) {
            var dy = ((g.y0 + y) - g.cy).abs() + rowH / 2.0;
            var half = dy >= g.r ? 0.0 : Math.sqrt(g.r * g.r - dy * dy);
            if (g.cx - half > lo) {
                lo = g.cx - half;
            }
            if (g.cx + half < hi) {
                hi = g.cx + half;
            }
            if (hi <= lo) {
                return [w / 2, 0] as Array<Number>;
            }
        }
        return [((lo + hi) / 2.0).toNumber(), (hi - lo).toNumber()] as Array<Number>;
    }

    // Centre y of row `row` when rows of the given heights are stacked in the cell: centred in
    // it when lean is 0, hard against the far edge when the stack is leaning away from a rim.
    // Always derived from the heights it is handed, so the fitter and the drawing code cannot
    // disagree about where a row ended up.
    function stackY(h as Number, heights as Array<Number>, row as Number,
            lean as Number) as Number {
        var total = 0;
        for (var i = 0; i < heights.size(); i++) {
            total += heights[i];
        }
        var y = (h - total) / 2;
        if (lean != 0 && total <= h - 2 * MARGIN) {
            y = lean > 0 ? h - MARGIN - total : MARGIN;
        }
        for (var i = 0; i < row; i++) {
            y += heights[i];
        }
        return y + heights[row] / 2;
    }

    // Largest font from `fonts` whose glyphs fit maxW x maxH for this text; the smallest
    // font in the ladder if none do (something is always better than nothing on the water).
    function fitFont(dc as Graphics.Dc, text as String, maxW as Number, maxH as Number,
            fonts as Array<Graphics.FontType>) as Graphics.FontType {
        for (var i = 0; i < fonts.size(); i++) {
            var f = fonts[i];
            if (dc.getFontHeight(f) <= maxH && dc.getTextWidthInPixels(text, f) <= maxW) {
                return f;
            }
        }
        return fonts[fonts.size() - 1];
    }

    // Heights of the rows a layout wants, largest font first, shrunk until the stack fits
    // the cell. Returns the chosen fonts (one per row) — the caller then knows both the
    // font and, via stackY(), where each row sits.
    //
    // `texts` are the widest strings each row will ever show, so the fit is worst-case and
    // the display cannot start clipping later in the session when the counts get bigger.
    function fitRows(dc as Graphics.Dc, w as Number, h as Number, texts as Array<String>,
            ladders as Array, g as Glass?, lean as Number) as Array<Graphics.FontType> {
        var n = texts.size();
        var chosen = new Array<Graphics.FontType>[n];
        var heights = new Array<Number>[n];
        // pass 1: every row gets the tallest font that fits the cell height budget alone
        var budget = (h - 2 * MARGIN) / n;
        for (var i = 0; i < n; i++) {
            chosen[i] = fitFont(dc, texts[i], w - 2 * MARGIN, budget,
                ladders[i] as Array<Graphics.FontType>);
            heights[i] = dc.getFontHeight(chosen[i]);
        }
        // pass 2: with the rows placed, re-fit each row to the width actually available
        // there — and then do it again, because a row that steps down MOVES every row in the
        // stack. It is tempting to assume one round is enough, since a shorter stack sits
        // closer to the middle of its cell; but the middle of a cell against the bottom rim is
        // itself well down the glass, so shrinking the flight line pushed the % above it
        // DOWNWARDS, into a chord narrower than the one it had just been measured against.
        // That is how a 129 px quadrant on the fr255 kept a number three pixels too wide.
        //
        // fitFont is capped by the height the row already has, so a round can only ever shrink
        // and the loop settles; three rounds is one more than any cell in the twelve layouts
        // Garmin offers has ever needed.
        for (var round = 0; round < REFITS; round++) {
            var settled = true;
            for (var i = 0; i < n; i++) {
                var y = stackY(h, heights, i, lean);
                var maxW = rowWindow(w, y, heights[i], g)[1];
                chosen[i] = fitFont(dc, texts[i], maxW, heights[i],
                    ladders[i] as Array<Graphics.FontType>);
                var fh = dc.getFontHeight(chosen[i]);
                if (fh != heights[i]) {
                    heights[i] = fh;
                    settled = false;
                }
            }
            if (settled) {
                break;
            }
        }
        return chosen;
    }

    function heightsOf(dc as Graphics.Dc, fonts as Array<Graphics.FontType>) as Array<Number> {
        var out = new Array<Number>[fonts.size()];
        for (var i = 0; i < fonts.size(); i++) {
            out[i] = dc.getFontHeight(fonts[i]);
        }
        return out;
    }
}
