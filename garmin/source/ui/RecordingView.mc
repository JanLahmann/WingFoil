import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;
import WingFoilCore;

// Turns-page metrics, file scope so the static width helpers (shared with the layout
// test) can reach them — class consts are instance-scoped in Monkey C.
const TURNS_SPLIT_GAP = 16;
const TURNS_WORD_GAP = 12;
const TURNS_TALLY_SEP = " · ";

// Cell geometry. The column offset is NOT a constant: the round display narrows fast below
// the equator, so each cell row splits the chord available at its own depth and only falls
// back to CELL_DX_MAX where there is room to spare.
const CELL_DX_MAX = 105;
const CELL_GUTTER = 10;

// Gap between a cell's glyph and the word beside it.
const GLYPH_GAP = 4;

// Foil-% bezel arc: pen width, and how far the arc's CENTRE line sits inside the glass.
// 5 + a pen of 6 puts the outer edge 2 px in — the same FIT_MARGIN the text respects.
const BEZEL_PEN = 6;
const BEZEL_INSET = 5;

// The flight-state ring on a HERO page. It normally owns the bezel; when the page also asks
// for the foil-% arc it steps inside so the two rings nest instead of painting over each other.
const RING_INSET = 7;
const RING_PEN = 10;
const RING_INSET_NESTED = 16;
const RING_PEN_NESTED = 6;

// Safety margin inside the glass, in pixels, used by every fit. 2 px is deliberately tight:
// the shipped Clock page puts "23:59" in FONT_NUMBER_THAI_HOT within a few pixels of the
// bezel and it reads well, so anything more forgiving would shrink screens that are fine.
const FIT_MARGIN = 2;

// The GRID4 block sits this far above centre. A 2x2 of FONT_LARGE cells plus a giant number
// is more content than a 454 px circle holds when centred — the bottom row's outer corners go
// off the glass. Lifting the block trades unused space at the top for cell width at the
// bottom, where the chord is the binding constraint.
const GRID_BIAS = 20;

// Font ladders, largest first. Giant slots walk the number fonts, everything else the text
// fonts; fitFont() picks the first that fits the chord it has been given.
var NUMBER_FONTS as Array<Graphics.FontType> = [
    Graphics.FONT_NUMBER_THAI_HOT, Graphics.FONT_NUMBER_HOT,
    Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD
];
var TEXT_FONTS as Array<Graphics.FontType> = [
    Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL,
    Graphics.FONT_TINY, Graphics.FONT_XTINY
];

// Timeline page bands (see drawTimelinePage).
const TL_STRIP_H = 44;
const TL_SPARK_H = 96;
const TL_DOT_R = 6;
const TL_DOT_GAP = 4;
const TL_MARGIN = 6;

// The on-water screens. Which screens exist, in what order, is PageModel's business — this
// class only knows how to paint a layout. Fonts are deliberately large: spray + chop make
// small text unreadable on the water. All vertical positions are stacked from
// dc.getFontHeight() so blocks can never overlap, on any fenix 8 variant, and the row-Y maths
// lives in static helpers the layout tests measure against the round glass.
class RecordingView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    // The celebration is a whole-screen overlay, so leaving the page keeps nothing on screen.
    function onHide() as Void {
        PbFlash.stop();
    }

    function onUpdate(dc as Dc) as Void {
        var c = getApp().controller;
        var i = PageNav.index;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        // A page that shows foil % anywhere gets it a second time as an arc round the glass —
        // the one number the rider glances at without reading.
        var foilArc = PageModel.pageHasMetric(i, PageModel.M_FOIL_PCT);
        var layout = PageModel.layoutAt(i);
        if (layout == PageModel.LAYOUT_HERO) {
            drawHeroPage(dc, c, i, foilArc);
        } else if (layout == PageModel.LAYOUT_GRID4) {
            drawGridPage(dc, c, i);
        } else if (layout == PageModel.LAYOUT_CELLS2) {
            drawCells2Page(dc, c, i);
        } else if (layout == PageModel.LAYOUT_RECORDS) {
            drawRecordsPage(dc, c);
        } else if (layout == PageModel.LAYOUT_TURNS) {
            drawTurnsPage(dc, c);
        } else if (layout == PageModel.LAYOUT_TIMELINE) {
            drawTimelinePage(dc, c);
        } else if (layout == PageModel.LAYOUT_CLOCK) {
            drawClockPage(dc, c, i);
        } else {
            // LAYOUT_MAP lives in MapPageView and never reaches here; anything else is a
            // property the firmware handed us out of range — fall back to something readable.
            drawHeroPage(dc, c, i, foilArc);
        }
        if (foilArc) {
            drawFoilBezel(dc, c);
        }
        // The celebration paints over the page, so it goes on before the PAUSED banner and
        // never after: a rider who pauses mid-flash must still see that he is paused, which is
        // why the banner carries its own opaque background rather than trusting the backdrop.
        if (PbFlash.active()) {
            drawPbFlash(dc);
        }
        if (c.state == SessionController.STATE_PAUSED) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
            dc.drawText(dc.getWidth() / 2, 18, Graphics.FONT_SMALL, "PAUSED",
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // ---- foil-% bezel arc ----
    // 12 o'clock, clockwise, green over a dark-gray track, hugging the inside of the bezel.
    // Garmin's arc angles run COUNTER-clockwise from 3 o'clock, so 12 o'clock is 90 deg and
    // sweeping clockwise subtracts. Two primitive calls and integer maths: nothing allocates.
    hidden function drawFoilBezel(dc as Dc, c as SessionController) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var r = cx - BEZEL_INSET - BEZEL_PEN / 2;
        dc.setPenWidth(BEZEL_PEN);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        var pct = c.engine.foilPct().toNumber();
        if (pct > 0) {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            if (pct >= 100) {
                dc.drawCircle(cx, cy, r);
            } else {
                dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 90, bezelEndDeg(pct));
            }
        }
        dc.setPenWidth(1);
    }

    // End angle of a `pct` sweep that starts at 12 o'clock and runs clockwise, normalised
    // into 0..359. Shared with the layout test.
    static function bezelEndDeg(pct as Number) as Number {
        var end = 90 - pct * 360 / 100;
        while (end < 0) {
            end += 360;
        }
        return end % 360;
    }

    // ---- PB celebration ----
    // The whole screen goes green for ~700 ms with the new best on it. Frame parity picks the
    // shade, which is what turns a flash into a pulse (see PbFlash).
    hidden function drawPbFlash(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var col = PbFlash.color();
        dc.setColor(col, col);
        dc.clear();
        var hHot = dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
        var hS = dc.getFontHeight(Graphics.FONT_SMALL);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (hHot + hS) / 2 + hS / 2, Graphics.FONT_SMALL, "NEW PB", CV);
        dc.drawText(cx, cy - (hHot + hS) / 2 + hS + hHot / 2, Graphics.FONT_NUMBER_HOT,
            AppSettings.speedToDisplay(PbFlash.best2sMps).format("%.1f"), CV);
        dc.drawText(cx, cy + (hHot + hS) / 2 + hS / 2, Graphics.FONT_SMALL,
            AppSettings.speedLabel(), CV);
    }

    const CV = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    // ---- chord fitting ----
    // Garmin's font heights are LINE heights: leading above and below the glyphs. Stacking
    // uses the full line height, because that is what keeps two rows from touching. Fitting
    // uses the ink — about three quarters of it — because that is what the round glass
    // actually clips. Both numbers come from the same dc, so every variant gets its own.

    static function inkH(dc as Dc, font as Graphics.FontType) as Number {
        return dc.getFontHeight(font) * 3 / 4;
    }

    // Half the chord available to a box of ink height `h` whose centre is `dy` from the middle.
    static function chordHalf(radius as Number, dy as Number, h as Number) as Number {
        var d = dy.abs() + h / 2;
        var v = radius * radius - d * d;
        return v > 0 ? Math.sqrt(v.toFloat()).toNumber() : 0;
    }

    // Widest text the row at `dy` can hold for a box of ink height `h`.
    static function rowBudget(radius as Number, dy as Number, h as Number) as Number {
        return 2 * chordHalf(radius, dy, h);
    }

    // Largest font in `ladder` at or after `from` that renders `text` within `maxW`.
    // Falls back to the last (smallest) entry rather than returning nothing.
    static function fitFont(dc as Dc, ladder as Array<Graphics.FontType>, from as Number,
            text as String, maxW as Number) as Graphics.FontType {
        for (var i = from; i < ladder.size() - 1; i++) {
            if (dc.getTextWidthInPixels(text, ladder[i]) <= maxW) {
                return ladder[i];
            }
        }
        return ladder[ladder.size() - 1];
    }

    static function fitRadius(dc as Dc) as Number {
        return dc.getWidth() / 2 - FIT_MARGIN;
    }

    // Column offset and per-cell half width for a cell row whose deepest ink is `dy` below the
    // centre: split that chord in two with a gutter, then cap the spread so a roomy row still
    // looks like the two-column grid it is. Returns [dx, halfWidth].
    static function cellColumns(radius as Number, dy as Number, h as Number)
            as Array<Number> {
        // each cell lives in ONE half of the chord, so the half-chord is the budget to split
        var w = (chordHalf(radius, dy, h) - CELL_GUTTER) / 2;
        var dx = CELL_GUTTER / 2 + w;
        if (dx > CELL_DX_MAX) {
            dx = CELL_DX_MAX;
            w = CELL_DX_MAX - CELL_GUTTER / 2;
        }
        return [dx, w];
    }

    // ---- HERO: one giant number, its unit line, and up to two rows under it ----
    // The default page 1 (speed / flight timer / HR) is exactly this. The foil-state ring is
    // part of the hero style: on the water the colour, not the number, is what you read first.
    hidden function drawHeroPage(dc as Dc, c as SessionController, page as Number,
            foilArc as Boolean) as Void {
        var e = c.engine;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc);
        var hN = dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);
        var hM = dc.getFontHeight(Graphics.FONT_MEDIUM);

        // state ring: green flying, dark gray off-foil. It steps inside when the page also
        // carries the foil-% arc, so the bezel holds exactly one ring at a time.
        var flying = e.detector.state == FlightDetector.STATE_ON;
        dc.setPenWidth(foilArc ? RING_PEN_NESTED : RING_PEN);
        dc.setColor(flying ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GRAY,
            Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, cx - (foilArc ? RING_INSET_NESTED : RING_INSET));
        dc.setPenWidth(1);

        // sub-rows compact upward, so leaving slot 2 empty does not leave a hole
        var sub1 = PageModel.slotAt(page, 1);
        var sub2 = PageModel.slotAt(page, 2);
        if (sub1 == PageModel.M_NONE) {
            sub1 = sub2;
            sub2 = PageModel.M_NONE;
        }
        var nSub = (sub1 != PageModel.M_NONE ? 1 : 0) + (sub2 != PageModel.M_NONE ? 1 : 0);

        var giant = PageModel.slotAt(page, 0);
        var gv = PageModel.value(giant, c);
        var y = heroRowY(cy, hN, hT, hL, hM, 0, nSub);
        var gFont = fitFont(dc, NUMBER_FONTS, 0, gv,
            rowBudget(radius, y - cy, inkH(dc, Graphics.FONT_NUMBER_THAI_HOT)));
        dc.setColor(PageModel.color(giant, c), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, gFont, gv, CV);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, heroRowY(cy, hN, hT, hL, hM, 1, nSub), Graphics.FONT_XTINY,
            PageModel.label(giant), CV);
        if (sub1 != PageModel.M_NONE) {
            drawFittedRow(dc, cx, cy, radius, heroRowY(cy, hN, hT, hL, hM, 2, nSub), 0,
                PageModel.value(sub1, c) + PageModel.suffix(sub1), PageModel.color(sub1, c));
        }
        if (sub2 != PageModel.M_NONE) {
            drawFittedRow(dc, cx, cy, radius, heroRowY(cy, hN, hT, hL, hM, 3, nSub), 1,
                PageModel.value(sub2, c) + PageModel.suffix(sub2), PageModel.color(sub2, c));
        }
    }

    // A centred text row that steps down the text ladder (starting at `from`) until it fits.
    hidden function drawFittedRow(dc as Dc, cx as Number, cy as Number, radius as Number,
            y as Number, from as Number, text as String, col as Number) as Void {
        var font = fitFont(dc, TEXT_FONTS, from, text,
            rowBudget(radius, y - cy, inkH(dc, TEXT_FONTS[from])));
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, font, text, CV);
    }

    // Row centres for HERO: 0 = giant number, 1 = unit line, 2 = first sub-row (LARGE),
    // 3 = second sub-row (MEDIUM). The block is centred on the rows it actually has, and the
    // giant's BAND is always the biggest number font's line height whatever font lands in it —
    // so the stack is deterministic and the fit can shrink the number without moving anything.
    static function heroRowY(cy as Number, hN as Number, hT as Number, hL as Number,
            hM as Number, row as Number, nSub as Number) as Number {
        var total = hN + hT + (nSub >= 1 ? hL : 0) + (nSub >= 2 ? hM : 0);
        var y = cy - total / 2;
        if (row == 0) {
            return y + hN / 2;
        }
        if (row == 1) {
            return y + hN + hT / 2;
        }
        if (row == 2) {
            return y + hN + hT + hL / 2;
        }
        return y + hN + hT + hL + hM / 2;
    }

    // ---- GRID4: optional giant number on top, then a 2x2 of label/value cells ----
    hidden function drawGridPage(dc as Dc, c as SessionController, page as Number) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc);
        var hG = dc.getFontHeight(Graphics.FONT_NUMBER_MILD);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);

        var giant = PageModel.slotAt(page, 0);
        var hasGiant = giant != PageModel.M_NONE;
        if (hasGiant) {
            var gv = PageModel.value(giant, c);
            var yg = gridRowY(cy, hG, hT, hL, 0, hasGiant);
            var gFont = fitFont(dc, NUMBER_FONTS, 3, gv,
                rowBudget(radius, yg - cy, inkH(dc, Graphics.FONT_NUMBER_MILD)));
            dc.setColor(PageModel.color(giant, c), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, yg, gFont, gv, CV);
        }
        drawCellRow(dc, c, cx, cy, radius, gridRowY(cy, hG, hT, hL, 1, hasGiant),
            PageModel.slotAt(page, 1), PageModel.slotAt(page, 2));
        drawCellRow(dc, c, cx, cy, radius, gridRowY(cy, hG, hT, hL, 2, hasGiant),
            PageModel.slotAt(page, 3), PageModel.slotAt(page, 4));
    }

    // Row centres for GRID4: 0 = giant number, 1 = top cell label, 2 = bottom cell label.
    // A cell's value sits (hT + hL) / 2 below its label. `hG` is the giant BAND — always
    // FONT_NUMBER_MILD's line height, because a 2x2 of FONT_LARGE cells plus anything taller
    // pushes the bottom row's corners off a 454 px circle. The whole block is lifted by
    // GRID_BIAS to buy that bottom row its width back.
    static function gridRowY(cy as Number, hG as Number, hT as Number, hL as Number,
            row as Number, hasGiant as Boolean) as Number {
        var cellH = hT + hL;
        var top = hasGiant ? cy - (hG + 2 * cellH) / 2 - GRID_BIAS : cy - cellH;
        if (row == 0) {
            return top + hG / 2;
        }
        var y = (hasGiant ? top + hG : top) + hT / 2;
        return row == 1 ? y : y + cellH;
    }

    // ---- CELLS2: two side-by-side cells, centred ----
    hidden function drawCells2Page(dc as Dc, c as SessionController, page as Number) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);
        drawCellRow(dc, c, cx, cy, fitRadius(dc), cells2RowY(cy, hT, hL),
            PageModel.slotAt(page, 0), PageModel.slotAt(page, 1));
    }

    // Label centre line for CELLS2; the value hangs (hT + hL) / 2 below it.
    static function cells2RowY(cy as Number, hT as Number, hL as Number) as Number {
        return cy - (hT + hL) / 2 + hT / 2;
    }

    // Two cells sharing one row's chord. The column offset comes from the depth of the row's
    // deepest ink, so the same code lays out a comfortable middle row and a tight bottom one.
    hidden function drawCellRow(dc as Dc, c as SessionController, cx as Number, cy as Number,
            radius as Number, y as Number, left as Number, right as Number) as Void {
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);
        var yv = y + (hT + hL) / 2;
        var col = cellColumns(radius, yv - cy, inkH(dc, Graphics.FONT_LARGE));
        drawSlotCell(dc, c, cx - col[0], y, yv, 2 * col[1], left);
        drawSlotCell(dc, c, cx + col[0], y, yv, 2 * col[1], right);
    }

    hidden function drawSlotCell(dc as Dc, c as SessionController, x as Number, y as Number,
            yv as Number, maxW as Number, id as Number) as Void {
        if (id == PageModel.M_NONE) {
            return;
        }
        drawCellLabel(dc, x, y, id);
        var value = PageModel.value(id, c);
        dc.setColor(PageModel.color(id, c), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, yv, fitFont(dc, TEXT_FONTS, 0, value, maxW), value, CV);
    }

    // A cell's label row: the metric's glyph, then — when showLabels is on — the word beside
    // it, the pair centred on the cell's column as one block. With labels off the glyph alone
    // carries the meaning, which is the whole point of drawing them.
    hidden function drawCellLabel(dc as Dc, x as Number, y as Number, id as Number) as Void {
        var g = PageModel.glyph(id);
        var s = Glyphs.size(dc);
        var label = AppSettings.showLabels ? PageModel.label(id) : "";
        var left = x - cellLabelWidth(dc, id, s, label) / 2;
        if (g != Glyphs.G_NONE) {
            Glyphs.draw(dc, g, left + s / 2, y, s, Graphics.COLOR_LT_GRAY);
            left += s + (label.length() > 0 ? GLYPH_GAP : 0);
        }
        if (label.length() > 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, y, Graphics.FONT_XTINY, label,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Width of that block. Shared with the layout test, which measures the label row against
    // the chord exactly as it measures the value row.
    static function cellLabelWidth(dc as Dc, id as Number, s as Number,
            label as String) as Number {
        var w = 0;
        if (PageModel.glyph(id) != Glyphs.G_NONE) {
            w = s;
            if (label.length() > 0) {
                w += GLYPH_GAP;
            }
        }
        return w + dc.getTextWidthInPixels(label, Graphics.FONT_XTINY);
    }

    // ---- RECORDS: live speed records, one giant number per block ----
    hidden function drawRecordsPage(dc as Dc, c as SessionController) as Void {
        var r = c.engine.records;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var hHot = dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var unit = " " + AppSettings.speedLabel();

        // biased 12 px down: the top label otherwise clips the circle edge;
        // unit only on the lower label to keep the top one narrow
        var y = cy + 12 - (2 * hHot + 2 * hT) / 2 + hT / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY, "best 2s", CV);
        y += (hT + hHot) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_NUMBER_HOT,
            AppSettings.speedToDisplay(r.best2sMps).format("%.1f"), CV);
        y += (hHot + hT) / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY, "best 10s" + unit, CV);
        y += (hT + hHot) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_NUMBER_HOT,
            AppSettings.speedToDisplay(r.best10sMps).format("%.1f"), CV);
    }

    // ---- TURNS: big count (tacks/jibes once a wind axis is set, total otherwise),
    // the last turn's outcome as a colour-coded word, its score, and the outcome tally ----
    hidden function drawTurnsPage(dc as Dc, c as SessionController) as Void {
        var t = c.engine.turns;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hHot = dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);
        var hS = dc.getFontHeight(Graphics.FONT_SMALL);
        var windSet = AppSettings.cfg.windDirection >= 0;

        var y = turnsRowY(cy, hT, hHot, hL, hS, 0);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY,
            windSet ? "tack / jibe  " + AppSettings.windLabel() : "turns", CV);

        // widest block on the vertical centre line, where the round display is widest
        y = turnsRowY(cy, hT, hHot, hL, hS, 1);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (windSet) {
            drawSplitCount(dc, cx, y, t.tackCount.toString(), t.jibeCount.toString());
        } else {
            dc.drawText(cx, y, Graphics.FONT_NUMBER_HOT, t.turnCount.toString(), CV);
        }

        // last outcome: the SYMBOL in its colour, then the score, centred as one phrase.
        // A check / triangle / cross is read before the eye has finished focusing, where
        // "TOUCH" has to be spelled out; the score stays FONT_LARGE beside it because the
        // number is the part that actually differs between two touchdowns.
        // Anchoring each half at the centre line instead put the old "TOUCH 100%" 412 px wide
        // on a 384 px chord at that depth — the round glass ate both ends.
        y = turnsRowY(cy, hT, hHot, hL, hS, 2);
        var sym = outcomeSymbol(t.lastOutcome);
        var symW = outcomeSymSize(dc);
        var col = outcomeColor(t.lastOutcome);
        var score = t.lastOutcome == TurnDetector.OUTCOME_NONE
            ? "--" : t.lastScorePct.toString() + "%";
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var x = cx - outcomeWidth(dc, symW, score) / 2;
        Glyphs.drawOutcome(dc, sym, x + symW / 2, y, symW, col);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + symW + TURNS_WORD_GAP, y, Graphics.FONT_LARGE, score, LV);

        // tally: flew · touchdown · swim, in the same colours as the symbol above
        drawTally(dc, cx, turnsRowY(cy, hT, hHot, hL, hS, 3), t);
    }

    static function outcomeSymbol(outcome as Number) as Number {
        if (outcome == TurnDetector.OUTCOME_FLEW) { return Glyphs.O_CHECK; }
        if (outcome == TurnDetector.OUTCOME_TOUCHDOWN) { return Glyphs.O_TRIANGLE; }
        if (outcome == TurnDetector.OUTCOME_FELL) { return Glyphs.O_CROSS; }
        return Glyphs.O_DASH;
    }

    // The outcome symbol's box: the ink height of the score beside it, so the two read as one
    // line whatever the variant's font metrics are.
    static function outcomeSymSize(dc as Dc) as Number {
        return inkH(dc, Graphics.FONT_LARGE);
    }

    static function outcomeColor(outcome as Number) as Number {
        if (outcome == TurnDetector.OUTCOME_FLEW) { return Graphics.COLOR_GREEN; }
        if (outcome == TurnDetector.OUTCOME_TOUCHDOWN) { return Graphics.COLOR_ORANGE; }
        if (outcome == TurnDetector.OUTCOME_FELL) { return Graphics.COLOR_RED; }
        return Graphics.COLOR_DK_GRAY;
    }

    // Row centre for the Turns page: 0 = header, 1 = counts, 2 = outcome, 3 = tally.
    // Stacked from font heights only, so the rows can never overlap on any variant.
    // Shared with the layout test, which asserts every row still clears the circle.
    static function turnsRowY(cy as Number, hT as Number, hHot as Number, hL as Number,
            hS as Number, row as Number) as Number {
        var y = cy - (hT + hHot + hL + hS) / 2 + hT / 2;
        if (row == 0) {
            return y;
        }
        y += (hT + hHot) / 2;
        if (row == 1) {
            return y;
        }
        y += (hHot + hL) / 2;
        return row == 2 ? y : y + (hL + hS) / 2;
    }

    // Total width of the "<symbol> <score>" block.
    static function outcomeWidth(dc as Dc, symW as Number, score as String) as Number {
        return symW + TURNS_WORD_GAP + dc.getTextWidthInPixels(score, Graphics.FONT_LARGE);
    }

    // Total width of the "<n> / <n>" block. Shared with the layout test, which asserts the
    // block still fits the circle at its row.
    static function splitCountWidth(dc as Dc, left as String, right as String) as Number {
        return dc.getTextWidthInPixels(left, Graphics.FONT_NUMBER_HOT)
            + dc.getTextWidthInPixels(right, Graphics.FONT_NUMBER_HOT)
            + dc.getTextWidthInPixels("/", Graphics.FONT_MEDIUM) + 2 * TURNS_SPLIT_GAP;
    }

    static function tallyWidth(dc as Dc, a as String, b as String, c as String) as Number {
        var f = Graphics.FONT_SMALL;
        return dc.getTextWidthInPixels(a, f) + dc.getTextWidthInPixels(b, f)
            + dc.getTextWidthInPixels(c, f) + 2 * dc.getTextWidthInPixels(TURNS_TALLY_SEP, f);
    }

    // Two giant counts with a separator, centred as one block.
    hidden function drawSplitCount(dc as Dc, cx as Number, y as Number, left as String,
            right as String) as Void {
        var f = Graphics.FONT_NUMBER_HOT;
        var wl = dc.getTextWidthInPixels(left, f);
        var ws = dc.getTextWidthInPixels("/", Graphics.FONT_MEDIUM);
        var x = cx - splitCountWidth(dc, left, right) / 2;
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.drawText(x, y, f, left, LV);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wl + TURNS_SPLIT_GAP, y, Graphics.FONT_MEDIUM, "/", LV);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wl + ws + 2 * TURNS_SPLIT_GAP, y, f, right, LV);
    }

    // "flew · touch · swim" counts, colour-coded, centred as one block.
    hidden function drawTally(dc as Dc, cx as Number, y as Number,
            t as TurnDetector) as Void {
        var f = Graphics.FONT_SMALL;
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var a = t.flewCount.toString();
        var b = t.touchdownCount.toString();
        var s = t.fellCount.toString();
        var wSep = dc.getTextWidthInPixels(TURNS_TALLY_SEP, f);
        var wa = dc.getTextWidthInPixels(a, f);
        var wb = dc.getTextWidthInPixels(b, f);
        var x = cx - tallyWidth(dc, a, b, s) / 2;
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, a, LV);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wa, y, f, TURNS_TALLY_SEP, LV);
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wa + wSep, y, f, b, LV);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wa + wSep + wb, y, f, TURNS_TALLY_SEP, LV);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wa + wb + 2 * wSep, y, f, s, LV);
    }

    // ---- TIMELINE: the session as a story ----
    // Three stacked bands: foil-fraction bars over the whole session, a max-speed sparkline
    // with the best-2s reference line, and the turn outcomes as coloured dots (newest right).
    // Every band is clipped to the chord at its own depth, so nothing runs off the glass; the
    // dot row simply shows as many of the most recent turns as fit.
    hidden function drawTimelinePage(dc as Dc, c as SessionController) as Void {
        var h = c.engine.history;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var radius = cx - TL_MARGIN;

        // band 1: foil-fraction bars
        var top = timelineRowY(cy, hT, 1);
        var halfW = bandHalfWidth(radius, top, top + TL_STRIP_H, cy);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, timelineRowY(cy, hT, 0), Graphics.FONT_XTINY, "on foil", CV);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - halfW, top + TL_STRIP_H, cx + halfW, top + TL_STRIP_H);
        var n = h.slotCount;
        if (n > 0) {
            var w = 2 * halfW;
            var barW = w / n;
            if (barW < 1) {
                barW = 1;
            }
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i < n; i++) {
                var bh = h.foilPct[i] * TL_STRIP_H / 100;
                if (bh > 0) {
                    dc.fillRectangle(cx - halfW + i * w / n, top + TL_STRIP_H - bh, barW, bh);
                }
            }
        }

        // band 2: max-speed sparkline + best-2s reference
        top = timelineRowY(cy, hT, 3);
        halfW = bandHalfWidth(radius, top, top + TL_SPARK_H, cy);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, timelineRowY(cy, hT, 2), Graphics.FONT_XTINY,
            "speed " + AppSettings.speedLabel(), CV);
        var peak = h.peakCms();
        var ref = (c.engine.records.best2sMps * 100.0).toNumber();
        if (ref > peak) {
            peak = ref;
        }
        if (peak < 100) {
            peak = 100;
        }
        if (ref > 0) {
            var yRef = top + TL_SPARK_H - ref * TL_SPARK_H / peak;
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx - halfW, yRef, cx + halfW, yRef);
        }
        if (n > 1) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            var px = cx - halfW;
            var py = top + TL_SPARK_H - h.maxCms[0] * TL_SPARK_H / peak;
            for (var i = 1; i < n; i++) {
                var qx = cx - halfW + i * 2 * halfW / (n - 1);
                var qy = top + TL_SPARK_H - h.maxCms[i] * TL_SPARK_H / peak;
                dc.drawLine(px, py, qx, qy);
                px = qx;
                py = qy;
            }
            dc.setPenWidth(1);
        }

        // band 3: turn outcomes, newest on the right
        var yDots = timelineRowY(cy, hT, 5);
        halfW = bandHalfWidth(radius, yDots - TL_DOT_R, yDots + TL_DOT_R, cy);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, timelineRowY(cy, hT, 4), Graphics.FONT_XTINY, "turns", CV);
        var shown = dotsShown(h.turnCount, 2 * halfW);
        var pitch = 2 * TL_DOT_R + TL_DOT_GAP;
        var x0 = cx - (shown * pitch - TL_DOT_GAP) / 2 + TL_DOT_R;
        for (var i = 0; i < shown; i++) {
            var outcome = h.turns[h.turnCount - shown + i];
            dc.setColor(outcomeColor(outcome), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x0 + i * pitch, yDots, TL_DOT_R);
        }
    }

    // Timeline rows: 0 foil label · 1 strip TOP · 2 speed label · 3 sparkline TOP ·
    // 4 turns label · 5 dot-row centre. Stacked from font heights + the band constants, so
    // the bands can never collide on any variant.
    static function timelineRowY(cy as Number, hT as Number, row as Number) as Number {
        var total = 3 * hT + TL_STRIP_H + TL_SPARK_H + 2 * TL_DOT_R;
        var y = cy - total / 2;
        if (row == 0) { return y + hT / 2; }
        if (row == 1) { return y + hT; }
        if (row == 2) { return y + hT + TL_STRIP_H + hT / 2; }
        if (row == 3) { return y + 2 * hT + TL_STRIP_H; }
        if (row == 4) { return y + 2 * hT + TL_STRIP_H + TL_SPARK_H + hT / 2; }
        return y + 3 * hT + TL_STRIP_H + TL_SPARK_H + TL_DOT_R;
    }

    // Half the chord available to a band spanning yTop..yBot — the deeper edge decides.
    static function bandHalfWidth(radius as Number, yTop as Number, yBot as Number,
            cy as Number) as Number {
        var d = (yTop - cy).abs();
        var d2 = (yBot - cy).abs();
        if (d2 > d) {
            d = d2;
        }
        var v = radius * radius - d * d;
        return v > 0 ? Math.sqrt(v.toFloat()).toNumber() : 0;
    }

    // How many outcome dots fit in `avail` pixels (newest win; the rest fall off the left).
    static function dotsShown(count as Number, avail as Number) as Number {
        var k = (avail + TL_DOT_GAP) / (2 * TL_DOT_R + TL_DOT_GAP);
        if (k > count) {
            k = count;
        }
        return k < 0 ? 0 : k;
    }

    // ---- CLOCK: giant time of day, then one configurable cell ----
    hidden function drawClockPage(dc as Dc, c as SessionController, page as Number) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc);
        var hN = dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);

        var now = PageModel.clockString();
        var y = clockRowY(cy, hN, hT, hL, 0);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, fitFont(dc, NUMBER_FONTS, 0, now,
            rowBudget(radius, y - cy, inkH(dc, Graphics.FONT_NUMBER_THAI_HOT))), now, CV);
        // battery deliberately absent from the default cell: non-important on the water (Jan)
        var yl = clockRowY(cy, hN, hT, hL, 1);
        var yv = yl + (hT + hL) / 2;
        drawSlotCell(dc, c, cx, yl, yv,
            rowBudget(radius, yv - cy, inkH(dc, Graphics.FONT_LARGE)),
            PageModel.slotAt(page, 0));
    }

    // Clock rows: 0 = giant time, 1 = cell label centre.
    static function clockRowY(cy as Number, hN as Number, hT as Number, hL as Number,
            row as Number) as Number {
        var y = cy - (hN + hT + hL) / 2 + hN / 2;
        return row == 0 ? y : y + hN / 2 + hT / 2;
    }

    static function fmtTime(seconds as Float) as String {
        return PageModel.fmtTime(seconds);
    }
}
