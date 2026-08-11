import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;
import WingFoilCore;

// Device-app unit tests (docs/testing.md layer 3). The detector/records/ring-buffer suite
// moved into the WingFoilCore barrel (barrel/WingFoilCore/tests/CoreTests.mc) when the core
// was extracted — it is compiled into this test binary through the barrelPath, so
// `monkeydo bin/WingFoilTests.prg fenix847mm -t` runs the barrel and the app suites together.

// ---- Round-display layout ----
// Round displays clip at the corners, not at a bounding box: a block that fits the width at
// the vertical centre can still lose its ends four rows down. These tests measure every row of
// every page layout with the device's real font metrics (a buffered-bitmap Dc) at its
// worst-case content and assert all four corners of each text box sit inside the glass. They
// are the headless twin of eyeballing a screenshot, and unlike a screenshot they run on every
// device.

const SCREEN = 454;                 // fenix 8 47 mm; the widest variant we ship
const BEZEL = 4.0;                  // margin the glass eats

// The furthest corner of a w x h text box centred at (cx, y), as a radius from the centre.
function cornerRadius(w as Number, h as Number, y as Number, cy as Number) as Float {
    var dy = (y - cy).abs() + h / 2.0;
    var dx = w / 2.0;
    return Math.sqrt(dx * dx + dy * dy);
}

// Same, for a box centred at x rather than on the centre line.
function cornerRadiusAt(cx as Number, x as Number, w as Number, h as Number, y as Number,
        cy as Number) as Float {
    var dx = (x - cx).abs() + w / 2.0;
    var dy = (y - cy).abs() + h / 2.0;
    return Math.sqrt(dx * dx + dy * dy);
}

function testDc() as Graphics.Dc {
    var ref = Graphics.createBufferedBitmap({:width => SCREEN, :height => SCREEN});
    var bmp = ref.get();
    Test.assertMessage(bmp != null, "buffered bitmap");
    return (bmp as Graphics.BufferedBitmap).getDc();
}

(:test)
function turnsPageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = SCREEN / 2;
    var radius = SCREEN / 2.0 - BEZEL;

    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hHot = dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
    var hL = dc.getFontHeight(Graphics.FONT_LARGE);
    var hS = dc.getFontHeight(Graphics.FONT_SMALL);

    // row 0: header, widest with a wind axis set
    var header = "tack / jibe  NNE";
    var r = cornerRadius(dc.getTextWidthInPixels(header, Graphics.FONT_XTINY), hT,
        RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 0), cy);
    Test.assertMessage(r <= radius, "header corner " + r.format("%.0f") + " > " + radius);

    // row 1: two 2-digit counts and the separator
    r = cornerRadius(RecordingView.splitCountWidth(dc, "99", "99"), hHot,
        RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 1), cy);
    Test.assertMessage(r <= radius, "counts corner " + r.format("%.0f") + " > " + radius);

    // row 2: longest outcome word next to the longest score
    r = cornerRadius(RecordingView.outcomeWidth(dc, "TOUCH", "100%"), hL,
        RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 2), cy);
    Test.assertMessage(r <= radius, "outcome corner " + r.format("%.0f") + " > " + radius);

    // row 3: three 2-digit tallies
    r = cornerRadius(RecordingView.tallyWidth(dc, "99", "99", "99"), hS,
        RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 3), cy);
    Test.assertMessage(r <= radius, "tally corner " + r.format("%.0f") + " > " + radius);

    // and the rows must not collide
    var y0 = RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 0);
    var y1 = RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 1);
    var y2 = RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 2);
    var y3 = RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 3);
    Test.assertMessage(y1 - y0 >= (hT + hHot) / 2, "header/counts gap");
    Test.assertMessage(y2 - y1 >= (hHot + hL) / 2, "counts/outcome gap");
    Test.assertMessage(y3 - y2 >= (hL + hS) / 2, "outcome/tally gap");
    logger.debug("turns page rows y=" + y0.toString() + "," + y1.toString() + ","
        + y2.toString() + "," + y3.toString() + " heights " + hT.toString() + ","
        + hHot.toString() + "," + hL.toString() + "," + hS.toString());
    return true;
}

// Every metric in the catalog, in the HERO giant slot and in both sub-rows. The renderer
// picks its fonts by fitting the chord, so the test drives the SAME fitters and asserts the
// result actually lands inside the glass — and that the fitter never had to shrink a value
// below FONT_MEDIUM, which would mean the layout is over-stuffed rather than merely tight.
(:test)
function heroPageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = SCREEN / 2;
    var radius = RecordingView.fitRadius(dc);
    var limit = radius.toFloat();
    var hN = dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT);
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hL = dc.getFontHeight(Graphics.FONT_LARGE);
    var hM = dc.getFontHeight(Graphics.FONT_MEDIUM);
    var shrunk = 0;

    for (var m = 1; m <= PageModel.M_MAX; m++) {
        var v = PageModel.worstValue(m);

        // giant slot
        var y0 = RecordingView.heroRowY(cy, hN, hT, hL, hM, 0, 2);
        var f = RecordingView.fitFont(dc, NUMBER_FONTS, 0, v,
            RecordingView.rowBudget(radius, y0 - cy, RecordingView.inkH(dc, NUMBER_FONTS[0])));
        var r = cornerRadius(dc.getTextWidthInPixels(v, f),
            RecordingView.inkH(dc, NUMBER_FONTS[0]), y0, cy);
        Test.assertMessage(r <= limit,
            "hero giant m" + m.toString() + " r=" + r.format("%.0f") + " > " + limit);
        if (f != NUMBER_FONTS[0]) { shrunk++; }

        // unit line
        r = cornerRadius(dc.getTextWidthInPixels(PageModel.worstLabel(m), Graphics.FONT_XTINY),
            RecordingView.inkH(dc, Graphics.FONT_XTINY),
            RecordingView.heroRowY(cy, hN, hT, hL, hM, 1, 2), cy);
        Test.assertMessage(r <= limit, "hero unit m" + m.toString() + " r=" + r.format("%.0f"));

        // the two sub-rows
        var sub = v + PageModel.suffix(m);
        for (var from = 0; from <= 1; from++) {
            var y = RecordingView.heroRowY(cy, hN, hT, hL, hM, 2 + from, 2);
            var ink = RecordingView.inkH(dc, TEXT_FONTS[from]);
            var tf = RecordingView.fitFont(dc, TEXT_FONTS, from, sub,
                RecordingView.rowBudget(radius, y - cy, ink));
            r = cornerRadius(dc.getTextWidthInPixels(sub, tf), ink, y, cy);
            Test.assertMessage(r <= limit, "hero sub" + from.toString() + " m" + m.toString()
                + " r=" + r.format("%.0f") + " > " + limit);
            Test.assertMessage(dc.getFontHeight(tf) >= dc.getFontHeight(TEXT_FONTS[from]),
                "hero sub" + from.toString() + " m" + m.toString() + " shrank below its font");
        }
    }
    // rows must not collide
    var a = RecordingView.heroRowY(cy, hN, hT, hL, hM, 1, 2);
    var b = RecordingView.heroRowY(cy, hN, hT, hL, hM, 2, 2);
    var d = RecordingView.heroRowY(cy, hN, hT, hL, hM, 3, 2);
    Test.assertMessage(b - a >= (hT + hL) / 2, "hero unit/sub1 gap");
    Test.assertMessage(d - b >= (hL + hM) / 2, "hero sub1/sub2 gap");
    // fewer sub-rows must pull the block back toward the centre, not leave a hole
    Test.assertMessage(RecordingView.heroRowY(cy, hN, hT, hL, hM, 0, 0)
        > RecordingView.heroRowY(cy, hN, hT, hL, hM, 0, 2), "hero recentres without sub-rows");
    Test.assertMessage(shrunk < PageModel.M_MAX,
        "every metric shrank the hero giant - band is wrong");
    logger.debug("hero: " + shrunk.toString() + " of " + PageModel.M_MAX.toString()
        + " metrics step the giant below THAI_HOT");
    return true;
}

// Every metric in the GRID4 giant slot and in all four cells, plus the CELLS2 row that reuses
// the same cell geometry.
(:test)
function gridAndCellsPagesFitRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cx = SCREEN / 2;
    var cy = SCREEN / 2;
    var radius = RecordingView.fitRadius(dc);
    var limit = radius.toFloat();
    var hG = dc.getFontHeight(Graphics.FONT_NUMBER_MILD);
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hL = dc.getFontHeight(Graphics.FONT_LARGE);
    var inkL = RecordingView.inkH(dc, Graphics.FONT_LARGE);
    var inkT = RecordingView.inkH(dc, Graphics.FONT_XTINY);
    var narrowest = 9999;

    for (var m = 1; m <= PageModel.M_MAX; m++) {
        var v = PageModel.worstValue(m);
        var lbl = PageModel.worstLabel(m);

        var yg = RecordingView.gridRowY(cy, hG, hT, hL, 0, true);
        var inkG = RecordingView.inkH(dc, Graphics.FONT_NUMBER_MILD);
        var gf = RecordingView.fitFont(dc, NUMBER_FONTS, 3, v,
            RecordingView.rowBudget(radius, yg - cy, inkG));
        var r = cornerRadius(dc.getTextWidthInPixels(v, gf), inkG, yg, cy);
        Test.assertMessage(r <= limit,
            "grid giant m" + m.toString() + " r=" + r.format("%.0f") + " > " + limit);

        for (var row = 1; row <= 2; row++) {
            var yl = RecordingView.gridRowY(cy, hG, hT, hL, row, true);
            var yv = yl + (hT + hL) / 2;
            var col = RecordingView.cellColumns(radius, yv - cy, inkL);
            var vf = RecordingView.fitFont(dc, TEXT_FONTS, 0, v, 2 * col[1]);
            if (2 * col[1] < narrowest) { narrowest = 2 * col[1]; }

            r = cornerRadiusAt(cx, cx + col[0], dc.getTextWidthInPixels(lbl,
                Graphics.FONT_XTINY), inkT, yl, cy);
            Test.assertMessage(r <= limit, "grid label m" + m.toString() + " row"
                + row.toString() + " r=" + r.format("%.0f") + " > " + limit);
            r = cornerRadiusAt(cx, cx + col[0], dc.getTextWidthInPixels(v, vf), inkL, yv, cy);
            Test.assertMessage(r <= limit, "grid value m" + m.toString() + " row"
                + row.toString() + " r=" + r.format("%.0f") + " > " + limit);
            Test.assertMessage(dc.getFontHeight(vf) >= dc.getFontHeight(Graphics.FONT_MEDIUM),
                "grid value m" + m.toString() + " row" + row.toString()
                    + " shrank below FONT_MEDIUM");
            // the two columns must not touch
            Test.assertMessage(col[0] - col[1] >= CELL_GUTTER / 2,
                "grid columns overlap at row " + row.toString());
        }

        // CELLS2 reuses the cell row, at the widest depth on the screen
        var y2 = RecordingView.cells2RowY(cy, hT, hL) + (hT + hL) / 2;
        var c2 = RecordingView.cellColumns(radius, y2 - cy, inkL);
        var f2 = RecordingView.fitFont(dc, TEXT_FONTS, 0, v, 2 * c2[1]);
        r = cornerRadiusAt(cx, cx + c2[0], dc.getTextWidthInPixels(v, f2), inkL, y2, cy);
        Test.assertMessage(r <= limit,
            "cells2 value m" + m.toString() + " r=" + r.format("%.0f") + " > " + limit);
        Test.assertEqual(f2, Graphics.FONT_LARGE);   // the roomiest row keeps the big font
    }

    var g1 = RecordingView.gridRowY(cy, hG, hT, hL, 1, true);
    var g2 = RecordingView.gridRowY(cy, hG, hT, hL, 2, true);
    Test.assertMessage(g2 - g1 >= hT + hL, "grid cell rows overlap");
    // without a giant the 2x2 centres on the screen instead of hanging under one
    Test.assertMessage(RecordingView.gridRowY(cy, hG, hT, hL, 1, false) < g1,
        "grid without a giant recentres");
    // ... and it centres exactly: the block's top edge and bottom edge are equidistant
    var topEdge = RecordingView.gridRowY(cy, hG, hT, hL, 1, false) - hT / 2;
    var botEdge = RecordingView.gridRowY(cy, hG, hT, hL, 2, false) + (hT + hL) / 2 + hL / 2;
    Test.assertMessage(((cy - topEdge) - (botEdge - cy)).abs() <= 1,   // integer rounding
        "grid block off centre: " + (cy - topEdge).toString() + " vs "
            + (botEdge - cy).toString());
    logger.debug("grid: narrowest cell budget " + narrowest.toString() + "px");
    return true;
}

// CLOCK page: giant time of day over one configurable cell.
(:test)
function clockPageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = SCREEN / 2;
    var radius = RecordingView.fitRadius(dc);
    var limit = radius.toFloat();
    var hN = dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT);
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hL = dc.getFontHeight(Graphics.FONT_LARGE);
    var inkN = RecordingView.inkH(dc, Graphics.FONT_NUMBER_THAI_HOT);
    var inkL = RecordingView.inkH(dc, Graphics.FONT_LARGE);

    var y = RecordingView.clockRowY(cy, hN, hT, hL, 0);
    var f = RecordingView.fitFont(dc, NUMBER_FONTS, 0, "23:59",
        RecordingView.rowBudget(radius, y - cy, inkN));
    var r = cornerRadius(dc.getTextWidthInPixels("23:59", f), inkN, y, cy);
    Test.assertMessage(r <= limit, "clock giant r=" + r.format("%.0f") + " > " + limit);

    var yv = RecordingView.clockRowY(cy, hN, hT, hL, 1) + (hT + hL) / 2;
    var budget = RecordingView.rowBudget(radius, yv - cy, inkL);
    for (var m = 1; m <= PageModel.M_MAX; m++) {
        var v = PageModel.worstValue(m);
        var vf = RecordingView.fitFont(dc, TEXT_FONTS, 0, v, budget);
        Test.assertEqual(vf, Graphics.FONT_LARGE);
        r = cornerRadius(dc.getTextWidthInPixels(v, vf), inkL, yv, cy);
        Test.assertMessage(r <= limit,
            "clock cell m" + m.toString() + " r=" + r.format("%.0f") + " > " + limit);
    }
    logger.debug("clock giant font height " + dc.getFontHeight(f).toString()
        + " (THAI_HOT is " + hN.toString() + "), cell budget " + budget.toString() + "px");
    return true;
}

// TIMELINE page at its worst case: 256 history slots and a full 64-turn outcome log.
(:test)
function timelinePageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cx = SCREEN / 2;
    var cy = SCREEN / 2;
    var radius = SCREEN / 2 - TL_MARGIN;
    var limit = SCREEN / 2.0 - BEZEL;
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);

    // bands, in draw order, must stack without overlapping and stay inside the glass
    var yStripTop = RecordingView.timelineRowY(cy, hT, 1);
    var ySparkTop = RecordingView.timelineRowY(cy, hT, 3);
    var yDots = RecordingView.timelineRowY(cy, hT, 5);
    Test.assertMessage(ySparkTop >= yStripTop + TL_STRIP_H + hT, "strip/spark overlap");
    Test.assertMessage(yDots - TL_DOT_R >= ySparkTop + TL_SPARK_H + hT, "spark/dots overlap");

    var hwStrip = RecordingView.bandHalfWidth(radius, yStripTop, yStripTop + TL_STRIP_H, cy);
    var hwSpark = RecordingView.bandHalfWidth(radius, ySparkTop, ySparkTop + TL_SPARK_H, cy);
    var hwDots = RecordingView.bandHalfWidth(radius, yDots - TL_DOT_R, yDots + TL_DOT_R, cy);
    Test.assertMessage(hwStrip > 100 && hwSpark > 100 && hwDots > 100,
        "timeline bands too narrow: " + hwStrip.toString() + "/" + hwSpark.toString()
            + "/" + hwDots.toString());

    // deepest corner of each band
    var r = cornerRadiusAt(cx, cx, 2 * hwStrip, TL_STRIP_H, yStripTop + TL_STRIP_H / 2, cy);
    Test.assertMessage(r <= limit, "strip corner " + r.format("%.0f") + " > " + limit);
    r = cornerRadiusAt(cx, cx, 2 * hwSpark, TL_SPARK_H, ySparkTop + TL_SPARK_H / 2, cy);
    Test.assertMessage(r <= limit, "spark corner " + r.format("%.0f") + " > " + limit);

    // 64 dots never all fit; the row shows the newest that do and stays inside the chord
    var shown = RecordingView.dotsShown(64, 2 * hwDots);
    Test.assertMessage(shown > 0 && shown <= 64, "dots shown " + shown.toString());
    var pitch = 2 * TL_DOT_R + TL_DOT_GAP;
    var halfRow = (shown * pitch - TL_DOT_GAP) / 2;
    Test.assertMessage(halfRow <= hwDots,
        "dot row " + halfRow.toString() + " > half chord " + hwDots.toString());
    r = cornerRadiusAt(cx, cx, 2 * halfRow, 2 * TL_DOT_R, yDots, cy);
    Test.assertMessage(r <= limit, "dots corner " + r.format("%.0f") + " > " + limit);
    Test.assertMessage(RecordingView.dotsShown(3, 2 * hwDots) == 3, "few dots all shown");
    Test.assertMessage(RecordingView.dotsShown(64, 0) == 0, "no room, no dots");

    // 256 slots must each get at least one pixel column
    Test.assertMessage(2 * hwStrip >= 256, "strip too narrow for 256 slots: "
        + (2 * hwStrip).toString());
    logger.debug("timeline strip " + (2 * hwStrip).toString() + "px spark "
        + (2 * hwSpark).toString() + "px dots " + shown.toString() + " of 64");
    return true;
}

// The digit-only number fonts are a documented trap: this logs which non-digit glyphs the
// device actually has, so a page that leans on one ("42%") is a deliberate choice, not a
// surprise. Informational — it asserts only that plain digits render.
(:test)
function numberFontGlyphCoverage(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var f = Graphics.FONT_NUMBER_HOT;
    Test.assertMessage(dc.getTextWidthInPixels("42", f) > 0, "digits render");
    logger.debug("FONT_NUMBER_HOT widths: '%'=" + dc.getTextWidthInPixels("%", f).toString()
        + " ':'=" + dc.getTextWidthInPixels(":", f).toString()
        + " '.'=" + dc.getTextWidthInPixels(".", f).toString()
        + " '-'=" + dc.getTextWidthInPixels("-", f).toString());
    return true;
}

// ---- Page model ----

// The out-of-the-box page set must be byte-for-byte the five screens the app shipped with.
(:test)
function pageModelDefaultsMatchShippedPages(logger as Test.Logger) as Boolean {
    PageModel.build({});
    Test.assertMessage(PageModel.count() == 5,
        "expected 5 default pages, got " + PageModel.count().toString());

    Test.assertEqual(PageModel.layoutAt(0), PageModel.LAYOUT_HERO);
    Test.assertEqual(PageModel.slotAt(0, 0), PageModel.M_SPEED);
    Test.assertEqual(PageModel.slotAt(0, 1), PageModel.M_FLIGHT_TIMER);
    Test.assertEqual(PageModel.slotAt(0, 2), PageModel.M_HR);

    Test.assertEqual(PageModel.layoutAt(1), PageModel.LAYOUT_GRID4);
    Test.assertEqual(PageModel.slotAt(1, 0), PageModel.M_FOIL_PCT);
    Test.assertEqual(PageModel.slotAt(1, 1), PageModel.M_FOIL_TIME);
    Test.assertEqual(PageModel.slotAt(1, 2), PageModel.M_LONGEST);
    Test.assertEqual(PageModel.slotAt(1, 3), PageModel.M_DISTANCE);
    Test.assertEqual(PageModel.slotAt(1, 4), PageModel.M_FLIGHTS);

    Test.assertEqual(PageModel.layoutAt(2), PageModel.LAYOUT_RECORDS);
    Test.assertEqual(PageModel.layoutAt(3), PageModel.LAYOUT_TURNS);
    Test.assertEqual(PageModel.layoutAt(4), PageModel.LAYOUT_CLOCK);
    Test.assertEqual(PageModel.slotAt(4, 0), PageModel.M_TIMER);

    // the cell labels the shipped Session page used, straight from the catalog
    Test.assertEqual(PageModel.label(PageModel.M_FOIL_TIME), "foil");
    Test.assertEqual(PageModel.label(PageModel.M_LONGEST), "longest");
    Test.assertEqual(PageModel.label(PageModel.M_DISTANCE), "km");
    Test.assertEqual(PageModel.label(PageModel.M_FLIGHTS), "flights");
    Test.assertEqual(PageModel.label(PageModel.M_TIMER), "timer");
    Test.assertEqual(PageModel.suffix(PageModel.M_HR), " bpm");

    // wrapping is total: no index can escape the page set
    Test.assertEqual(PageModel.wrap(-1), 4);
    Test.assertEqual(PageModel.wrap(5), 0);
    Test.assertMessage(!PageModel.mapPage, "map off by default");
    logger.debug("defaults: 5 pages, hero/grid4/records/turns/clock");
    return true;
}

// A rider's custom set: re-ordered, one page removed, junk values sanitised.
(:test)
function pageModelCustomConfigMaps(logger as Test.Logger) as Boolean {
    PageModel.build({
        "pg1Layout" => PageModel.LAYOUT_TIMELINE,
        "pg2Layout" => PageModel.LAYOUT_CELLS2,
        "pg2s1" => PageModel.M_BEST_2S,
        "pg2s2" => PageModel.M_BEST_10S,
        "pg3Layout" => PageModel.LAYOUT_OFF,
        "pg4Layout" => 99,                       // out of range -> off
        "pg5Layout" => PageModel.LAYOUT_GRID4,
        "pg5s1" => 42,                           // out of range -> none
        "pg5s2" => PageModel.M_BATTERY,
        "pg6Layout" => PageModel.LAYOUT_OFF
    });
    Test.assertMessage(PageModel.count() == 3,
        "expected 3 pages, got " + PageModel.count().toString());
    Test.assertEqual(PageModel.layoutAt(0), PageModel.LAYOUT_TIMELINE);
    Test.assertEqual(PageModel.layoutAt(1), PageModel.LAYOUT_CELLS2);
    Test.assertEqual(PageModel.slotAt(1, 0), PageModel.M_BEST_2S);
    Test.assertEqual(PageModel.slotAt(1, 1), PageModel.M_BEST_10S);
    Test.assertEqual(PageModel.layoutAt(2), PageModel.LAYOUT_GRID4);
    Test.assertEqual(PageModel.slotAt(2, 0), PageModel.M_NONE);
    Test.assertEqual(PageModel.slotAt(2, 1), PageModel.M_BATTERY);
    Test.assertEqual(PageModel.wrap(3), 0);

    // a map page is only offered where MapTrackView exists
    PageModel.build({
        "pg1Layout" => PageModel.LAYOUT_MAP,
        "pg2Layout" => PageModel.LAYOUT_OFF, "pg3Layout" => PageModel.LAYOUT_OFF,
        "pg4Layout" => PageModel.LAYOUT_OFF, "pg5Layout" => PageModel.LAYOUT_OFF,
        "pg6Layout" => PageModel.LAYOUT_OFF
    });
    if (PageModel.hasMap()) {
        Test.assertEqual(PageModel.layoutAt(0), PageModel.LAYOUT_MAP);
        Test.assertMessage(PageModel.mapPage, "map page flag set");
    } else {
        Test.assertEqual(PageModel.layoutAt(0), PageModel.LAYOUT_HERO);   // blank-screen guard
    }

    // every page off must still leave one readable screen
    PageModel.build({
        "pg1Layout" => 0, "pg2Layout" => 0, "pg3Layout" => 0,
        "pg4Layout" => 0, "pg5Layout" => 0, "pg6Layout" => 0
    });
    Test.assertEqual(PageModel.count(), 1);
    Test.assertEqual(PageModel.layoutAt(0), PageModel.LAYOUT_HERO);
    Test.assertEqual(PageModel.slotAt(0, 0), PageModel.M_SPEED);

    PageModel.build({});   // leave the defaults in place for the other tests
    logger.debug("custom config, junk sanitising and the all-off guard all map correctly");
    return true;
}

// ---- Auto-pause ----

(:test)
function autoPauseStateMachine(logger as Test.Logger) as Boolean {
    var ap = new AutoPause();

    // disabled: never fires, however long the rider floats
    ap.enabled = false;
    for (var i = 0; i < 30; i++) {
        Test.assertEqual(ap.tick(1.0, 0.0, true), AutoPause.EV_NONE);
    }

    ap.enabled = true;
    ap.delayS = 5;

    // riding: nothing happens
    for (var i = 0; i < 10; i++) {
        Test.assertEqual(ap.tick(1.0, 8.0, true), AutoPause.EV_NONE);
    }
    // slow, but the delay keeps resetting on every burst of speed
    Test.assertEqual(ap.tick(1.0, 0.2, true), AutoPause.EV_NONE);
    Test.assertEqual(ap.tick(1.0, 0.2, true), AutoPause.EV_NONE);
    Test.assertEqual(ap.tick(1.0, 5.0, true), AutoPause.EV_NONE);
    for (var i = 0; i < 4; i++) {
        Test.assertMessage(ap.tick(1.0, 0.3, true) == AutoPause.EV_NONE,
            "paused early at " + i.toString());
    }
    // fifth slow second crosses the delay
    Test.assertEqual(ap.tick(1.0, 0.3, true), AutoPause.EV_PAUSE);
    Test.assertMessage(ap.ownsPause(), "auto-pause owns the pause");

    // still drifting: stays paused
    for (var i = 0; i < 20; i++) {
        Test.assertEqual(ap.tick(1.0, 0.4, false), AutoPause.EV_NONE);
    }
    // moving again: resumes on the first real sample
    Test.assertEqual(ap.tick(1.0, 1.4, false), AutoPause.EV_RESUME);
    Test.assertMessage(!ap.ownsPause(), "ownership released on resume");
    Test.assertEqual(ap.tick(1.0, 1.4, true), AutoPause.EV_NONE);

    // a MANUAL pause (reset clears ownership) is never auto-resumed
    ap.reset();
    for (var i = 0; i < 20; i++) {
        Test.assertEqual(ap.tick(1.0, 9.0, false), AutoPause.EV_NONE);
    }

    // short delay, sub-second samples: the accumulator is in seconds, not ticks
    var fast = new AutoPause();
    fast.enabled = true;
    fast.delayS = 3;
    var ev = AutoPause.EV_NONE;
    for (var i = 0; i < 5; i++) {
        ev = fast.tick(0.5, 0.0, true);
        Test.assertEqual(ev, AutoPause.EV_NONE);
    }
    Test.assertEqual(fast.tick(0.5, 0.0, true), AutoPause.EV_PAUSE);
    logger.debug("auto-pause: delay honoured, resume gated on ownership");
    return true;
}

// ---- Session history (Timeline backing store) ----

(:test)
function historyBufferDownsamplesWhenFull(logger as Test.Logger) as Boolean {
    var h = new SessionHistory();
    Test.assertEqual(h.slotCount, 0);
    Test.assertEqual(h.slotS, h.SLOT_BASE_S);

    // half a slot of flying, half off foil -> 50%
    for (var s = 0; s < 4; s++) {
        for (var i = 0; i < h.SLOT_BASE_S; i++) {
            h.tick(1.0, i < h.SLOT_BASE_S / 2, 5.0 + s);
        }
    }
    Test.assertEqual(h.slotCount, 4);
    Test.assertMessage(h.foilPct[0] >= 45 && h.foilPct[0] <= 55,
        "foil fraction " + h.foilPct[0].toString());
    Test.assertEqual(h.maxCms[3], 800);
    Test.assertEqual(h.peakCms(), 800);

    // fill to the brim, then push past it
    while (h.slotCount < h.SLOT_MAX) {
        for (var i = 0; i < h.slotS; i++) {
            h.tick(1.0, true, 10.0);
        }
    }
    Test.assertEqual(h.slotCount, h.SLOT_MAX);
    Test.assertEqual(h.slotS, h.SLOT_BASE_S);
    var peakBefore = h.peakCms();

    for (var i = 0; i < h.slotS; i++) {
        h.tick(1.0, true, 12.0);
    }
    Test.assertMessage(h.slotCount == h.SLOT_MAX / 2 + 1,
        "after halving expected " + (h.SLOT_MAX / 2 + 1).toString()
            + " slots, got " + h.slotCount.toString());
    Test.assertEqual(h.slotS, 2 * h.SLOT_BASE_S);
    Test.assertMessage(h.peakCms() >= peakBefore, "peak survives the halving");

    // and it keeps halving rather than overflowing
    while (h.slotCount < h.SLOT_MAX) {
        for (var i = 0; i < h.slotS; i++) {
            h.tick(1.0, true, 9.0);
        }
    }
    for (var i = 0; i < h.slotS; i++) {
        h.tick(1.0, true, 9.0);
    }
    Test.assertMessage(h.slotCount <= h.SLOT_MAX, "never overflows");
    Test.assertEqual(h.slotS, 4 * h.SLOT_BASE_S);
    logger.debug("history: 256 slots @30s -> halves to " + h.slotCount.toString()
        + " @" + h.slotS.toString() + "s");
    return true;
}

(:test)
function turnOutcomeLogCapsAndDropsOldest(logger as Test.Logger) as Boolean {
    var h = new SessionHistory();
    for (var i = 0; i < h.TURN_MAX; i++) {
        h.logTurn(TurnDetector.OUTCOME_FLEW);
    }
    Test.assertEqual(h.turnCount, h.TURN_MAX);
    Test.assertEqual(h.turns[0], TurnDetector.OUTCOME_FLEW);

    // 40 more: the log stays capped and the oldest FLEWs fall off the front
    for (var i = 0; i < 40; i++) {
        h.logTurn(TurnDetector.OUTCOME_FELL);
    }
    Test.assertEqual(h.turnCount, h.TURN_MAX);
    Test.assertEqual(h.turns[h.TURN_MAX - 1], TurnDetector.OUTCOME_FELL);
    Test.assertEqual(h.turns[h.TURN_MAX - 40], TurnDetector.OUTCOME_FELL);
    Test.assertEqual(h.turns[h.TURN_MAX - 41], TurnDetector.OUTCOME_FLEW);
    logger.debug("turn log capped at " + h.TURN_MAX.toString() + ", oldest dropped");
    return true;
}

// ---- Renderer smoke test ----
// The screenshot pass is the ground truth for "does it look right"; this is the part of it
// that can run headlessly and on every device: actually PAINT every layout, at worst-case
// content, into a buffered bitmap. It catches what the geometry tests cannot — a null field
// dereferenced, a divide by zero in the timeline's scaling, a font constant that does not
// exist on this variant — because it runs the real onUpdate path, not a model of it.
// LAYOUT_MAP is absent on purpose: MapTrackView is the firmware's own View and cannot be
// drawn into an offscreen Dc.
(:test)
function everyLayoutRendersHeadless(logger as Test.Logger) as Boolean {
    var ref = Graphics.createBufferedBitmap({:width => SCREEN, :height => SCREEN});
    var bmp = ref.get();
    Test.assertMessage(bmp != null, "buffered bitmap");
    var dc = (bmp as Graphics.BufferedBitmap).getDc();

    // a session with something to show on every page
    var c = getApp().controller;
    var e = c.engine;
    e.speedMps = 11.4;
    e.distM = 18450.0;
    e.timerS = 7199.0;
    e.hr = 168;
    for (var i = 0; i < 300; i++) {
        e.history.tick(1.0, i % 3 != 0, 4.0 + (i % 17));
    }
    for (var i = 0; i < 70; i++) {
        e.history.logTurn(i % 3 + 1);
    }
    Test.assertEqual(e.history.turnCount, e.history.TURN_MAX);

    var layouts = [PageModel.LAYOUT_HERO, PageModel.LAYOUT_GRID4, PageModel.LAYOUT_CELLS2,
        PageModel.LAYOUT_RECORDS, PageModel.LAYOUT_TURNS, PageModel.LAYOUT_CLOCK,
        PageModel.LAYOUT_TIMELINE];
    var view = new RecordingView();
    for (var i = 0; i < layouts.size(); i++) {
        // every slot filled with a timer: the widest thing the catalog can produce
        PageModel.build({
            "pg1Layout" => layouts[i],
            "pg1s1" => PageModel.M_TIMER, "pg1s2" => PageModel.M_LONGEST,
            "pg1s3" => PageModel.M_HR, "pg1s4" => PageModel.M_FOIL_TIME,
            "pg1s5" => PageModel.M_BEST_10S,
            "pg2Layout" => 0, "pg3Layout" => 0, "pg4Layout" => 0,
            "pg5Layout" => 0, "pg6Layout" => 0
        });
        PageNav.index = 0;
        Test.assertEqual(PageModel.layoutAt(0), layouts[i]);
        view.onUpdate(dc);
    }

    // and the shipped default set, page by page, including the PAUSED banner
    PageModel.build({});
    for (var i = 0; i < PageModel.count(); i++) {
        PageNav.index = i;
        view.onUpdate(dc);
    }
    var was = c.state;
    c.state = SessionController.STATE_PAUSED;
    PageNav.index = 0;
    view.onUpdate(dc);
    c.state = was;

    // an empty session must render too — zero history, no records, no turns
    var fresh = new MetricsEngine();
    var saved = c.engine;
    c.engine = fresh;
    for (var i = 0; i < layouts.size(); i++) {
        PageModel.build({"pg1Layout" => layouts[i], "pg2Layout" => 0, "pg3Layout" => 0,
            "pg4Layout" => 0, "pg5Layout" => 0, "pg6Layout" => 0});
        PageNav.index = 0;
        view.onUpdate(dc);
    }
    c.engine = saved;
    PageModel.build({});
    PageNav.index = 0;
    logger.debug("rendered " + layouts.size().toString()
        + " layouts populated + empty, plus the 5 default pages and the PAUSED banner");
    return true;
}
