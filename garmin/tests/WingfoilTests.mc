import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;
import WingFoilCore;

// Device-app unit tests (docs/testing.md layer 3). The detector/records/ring-buffer suite
// moved into the WingFoilCore barrel (barrel/WingFoilCore/tests/CoreTests.mc) when the core
// was extracted — it is compiled into this test binary through the barrelPath, so
// `monkeydo bin/WingFoilTests.prg fenix847mm -t` still runs all 16 tests.

// ---- Turns page layout ----
// Round displays clip at the corners, not at a bounding box: a block that fits the width at
// the vertical centre can still lose its ends four rows down. This measures every row of the
// Turns page with the device's real font metrics (a buffered-bitmap Dc) at its worst-case
// content and asserts all four corners of each text box sit inside the glass. It is the
// headless twin of eyeballing a screenshot, and unlike a screenshot it runs on every device.

// The furthest corner of a w x h text box centred at (cx, y), as a radius from the centre.
function cornerRadius(w as Number, h as Number, y as Number, cy as Number) as Float {
    var dy = (y - cy).abs() + h / 2.0;
    var dx = w / 2.0;
    return Math.sqrt(dx * dx + dy * dy);
}

(:test)
function turnsPageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var ref = Graphics.createBufferedBitmap({:width => 454, :height => 454});
    var bmp = ref.get();
    Test.assertMessage(bmp != null, "buffered bitmap");
    var dc = (bmp as Graphics.BufferedBitmap).getDc();
    var cy = 227;
    var radius = 227.0 - 4.0;      // 4 px of bezel margin

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

