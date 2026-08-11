import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Layout maths for a data field, which — unlike the device app's own views — has no idea in
// advance how big its canvas is: the user drops it into a 1-, 2-, 3- or 4-field page and the
// system hands us whatever rectangle is left. Everything here is static and Dc-driven so the
// unit tests can measure the real device fonts and prove nothing clips, on any cell size.
//
// Two rules keep it readable on the water:
//   1. rows are stacked from dc.getFontHeight() only, so they can never overlap;
//   2. every row picks the LARGEST font that still fits its own width budget — and on a
//      full-screen round cell that budget is the chord of the circle at that row's height,
//      not the bounding box, because a round display clips at the corners.
module FieldLayout {
    enum {
        SIZE_SMALL = 0,     // 3- or 4-field cell: 2 numbers, nothing else
        SIZE_WIDE = 1,      // 2-field cell (or a wide 3-field row): 3 rows
        SIZE_FULL = 2       // 1-field page: the rich grid
    }

    // Pixels of bezel/edge margin kept clear on every side.
    const MARGIN = 4;

    // Largest-first font ladders. fitFont() walks them and takes the first that fits.
    const NUM_FONTS = [Graphics.FONT_NUMBER_THAI_HOT, Graphics.FONT_NUMBER_HOT,
        Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD, Graphics.FONT_LARGE,
        Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY,
        Graphics.FONT_XTINY] as Array<Graphics.FontType>;
    const TEXT_FONTS = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL,
        Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontType>;

    // Which layout a cell of this size gets. Thresholds are fractions of the device screen,
    // so one rule covers 416/454 AMOLED and 260/280 MIP fenix 8 variants.
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

    // True when the cell IS the (round) screen, i.e. the corners are missing glass.
    // A partial cell is a rectangle carved out of the middle and can use its full width.
    function isRoundFull(w as Number, h as Number, screenW as Number,
            screenH as Number) as Boolean {
        return screenW == screenH && classify(w, h, screenW, screenH) == SIZE_FULL;
    }

    // Usable width for a row of height rowH centred at y. On a round full-screen cell this
    // is the chord at the row's furthest edge from the centre — the same geometry the device
    // app's Turns-page test asserts, applied ahead of time instead of after the fact.
    function rowWidth(w as Number, h as Number, y as Number, rowH as Number,
            round as Boolean) as Number {
        if (!round) {
            return w - 2 * MARGIN;
        }
        var r = w / 2.0 - MARGIN;
        var dy = (y - h / 2.0).abs() + rowH / 2.0;
        if (dy >= r) {
            return 0;
        }
        return (2.0 * Math.sqrt(r * r - dy * dy)).toNumber();
    }

    // Centre y of row `row` when rows of the given heights are stacked centred in the cell.
    function stackY(h as Number, heights as Array<Number>, row as Number) as Number {
        var total = 0;
        for (var i = 0; i < heights.size(); i++) {
            total += heights[i];
        }
        var y = (h - total) / 2;
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
            ladders as Array, round as Boolean) as Array<Graphics.FontType> {
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
        // pass 2: with the rows placed, re-fit each to the width actually available there
        for (var i = 0; i < n; i++) {
            var y = stackY(h, heights, i);
            var maxW = rowWidth(w, h, y, heights[i], round);
            chosen[i] = fitFont(dc, texts[i], maxW, heights[i],
                ladders[i] as Array<Graphics.FontType>);
            heights[i] = dc.getFontHeight(chosen[i]);
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
