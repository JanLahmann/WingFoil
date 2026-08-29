import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
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

// The canvas every layout test measures on: THIS device's glass, not a fixed size. It used to
// be a const 454 (fenix 8 47 mm), which quietly made the suite meaningless on any smaller
// variant — a 240 px fenix 7S renders its rows into a 240 px chord but was asserted against a
// 454 px one, so nothing could ever fail. Reading it from the device is what makes
// "they run on every device" above actually true; the fenix 7 family (240/260/280 px MIP) is
// the reason it matters.
function screenPx() as Number {
    return System.getDeviceSettings().screenWidth;
}
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
    var ref = Graphics.createBufferedBitmap({:width => screenPx(), :height => screenPx()});
    var bmp = ref.get();
    Test.assertMessage(bmp != null, "buffered bitmap");
    return (bmp as Graphics.BufferedBitmap).getDc();
}

// ---- FIT developer-field schema ----
// The regression net for the beta-0.5.0 crash: 20 SESSION developer fields, a hard limit of
// 16, and no catchable error — the 17th createField killed the app on START. FitSchema's
// table is now the only place fields are declared, and these tests fail the build before a
// row that breaks a limit can reach a watch.

(:test)
function fitSchemaFitsDeviceBudgets(logger as Test.Logger) as Boolean {
    for (var m = 0; m < FitSchema.MSG_COUNT; m++) {
        var fields = FitSchema.fieldCount(m);
        var bytes = FitSchema.byteCount(m);
        logger.debug("msg " + m.toString() + ": " + fields.toString() + " fields, "
            + bytes.toString() + " B");
        // The hard one. Over it the runtime does not throw — it kills the app with
        // "System Error: Failed invoking <symbol>".
        Test.assertMessage(fields <= FitSchema.LIMIT_FIELDS,
            "message type " + m.toString() + " declares " + fields.toString()
            + " developer fields, the device accepts " + FitSchema.LIMIT_FIELDS.toString());
        Test.assertMessage(bytes <= FitSchema.LIMIT_BYTES,
            "message type " + m.toString() + " is " + bytes.toString() + " B, budget is "
            + FitSchema.LIMIT_BYTES.toString());
    }
    // Self-imposed headroom, so the next row added trips a test with room to spare.
    var ses = FitSchema.fieldCount(FitSchema.MSG_SESSION);
    Test.assertMessage(ses <= FitSchema.SESSION_FIELD_TARGET,
        "session declares " + ses.toString() + " fields, target is "
        + FitSchema.SESSION_FIELD_TARGET.toString() + " (limit "
        + FitSchema.LIMIT_FIELDS.toString() + ")");
    // The 1 Hz record message is a battery/storage budget too (docs/fit-schema.md).
    Test.assertMessage(FitSchema.byteCount(FitSchema.MSG_RECORD)
        <= FitSchema.RECORD_BYTES_TARGET, "record message over its 6 B/s target");
    Test.assertMessage(FitSchema.fits(), "fits() agrees with the assertions above");

    // The table must be complete and consistent, or a row could describe one field and
    // create another.
    Test.assertMessage(FitSchema.MSGS.size() == FitSchema.SLOT_COUNT, "an msg per slot");
    Test.assertMessage(FitSchema.IDS.size() == FitSchema.SLOT_COUNT, "an id per slot");
    Test.assertMessage(FitSchema.NAMES.size() == FitSchema.SLOT_COUNT, "a name per slot");
    Test.assertMessage(FitSchema.TYPES.size() == FitSchema.SLOT_COUNT, "a type per slot");
    Test.assertMessage(FitSchema.WIDTHS.size() == FitSchema.SLOT_COUNT, "a width per slot");
    Test.assertMessage(FitSchema.UNITS.size() == FitSchema.SLOT_COUNT, "a unit per slot");

    // Ids are unique *within* a message type (the same id in two message types is legal and
    // intentional), and the declared width must match the declared base type.
    for (var i = 0; i < FitSchema.SLOT_COUNT; i++) {
        var t = FitSchema.TYPES[i];
        var w = FitSchema.WIDTHS[i];
        var want = t == FitSchema.T_UINT8 ? 1
            : (t == FitSchema.T_UINT16 ? 2 : (t == FitSchema.T_UINT32 ? 4 : w));
        Test.assertMessage(w == want, FitSchema.NAMES[i] + " width " + w.toString()
            + " does not match its base type");
        for (var j = i + 1; j < FitSchema.SLOT_COUNT; j++) {
            Test.assertMessage(FitSchema.MSGS[i] != FitSchema.MSGS[j]
                || FitSchema.IDS[i] != FitSchema.IDS[j],
                "duplicate field id " + FitSchema.IDS[i].toString() + " in message type "
                + FitSchema.MSGS[i].toString());
        }
    }
    return true;
}

(:test)
function fitSchemaPackedFieldsRoundTrip(logger as Test.Logger) as Boolean {
    // 54 cfg_pack — must be byte-for-byte the data field's SessionPack.packCfg, since a
    // parser unpacks class (a) and class (d) files with the same shifts.
    var cfg = FitSchema.packCfg(1200, 800, 5);
    Test.assertMessage(FitSchema.cfgEntryCms(cfg) == 1200, "entry survives");
    Test.assertMessage(FitSchema.cfgExitCms(cfg) == 800, "exit survives");
    Test.assertMessage(FitSchema.cfgMinFlightS(cfg) == 5, "minFlight survives");
    Test.assertMessage(cfg == SessionPackEncoding(1200, 800, 5),
        "cfg_pack differs from the documented encoding");
    // Clamped, not wrapped: an out-of-range value must not bleed into a neighbouring field.
    var wide = FitSchema.packCfg(99999, 9999, 99);
    Test.assertMessage(FitSchema.cfgEntryCms(wide) == 65535, "entry clamps");
    Test.assertMessage(FitSchema.cfgExitCms(wide) == 2047, "exit clamps");
    Test.assertMessage(FitSchema.cfgMinFlightS(wide) == 31, "minFlight clamps");

    // 55 takeoff_pack — avgPumpsX10 | attempts | successes
    var to = FitSchema.packTakeoff(87, 12, 9);
    Test.assertMessage(FitSchema.takeoffAvgPumpsX10(to) == 87, "avg pumps survives");
    Test.assertMessage(FitSchema.takeoffAttempts(to) == 12, "attempts survives");
    Test.assertMessage(FitSchema.takeoffSuccesses(to) == 9, "successes survives");
    var toWide = FitSchema.packTakeoff(400, 300, 300);
    Test.assertMessage(FitSchema.takeoffAvgPumpsX10(toWide) == 255, "avg pumps clamps");
    Test.assertMessage(FitSchema.takeoffAttempts(toWide) == 255, "attempts clamps");
    Test.assertMessage(FitSchema.takeoffSuccesses(toWide) == 255, "successes clamps");

    // 56 longest_pack — seconds | metres
    var lp = FitSchema.packLongest(423, 5120);
    Test.assertMessage(FitSchema.longestS(lp) == 423, "longest seconds survives");
    Test.assertMessage(FitSchema.longestM(lp) == 5120, "longest metres survives");
    var lpWide = FitSchema.packLongest(70000, 70000);
    Test.assertMessage(FitSchema.longestS(lpWide) == 65535, "longest seconds clamps");
    Test.assertMessage(FitSchema.longestM(lpWide) == 65535, "longest metres clamps");

    // Negatives floor at 0 rather than sign-extending across the whole word.
    Test.assertMessage(FitSchema.packLongest(-1, -1) == 0, "negatives floor at 0");
    return true;
}

// The docs/fit-schema.md cfg_pack layout written out longhand, independent of FitSchema's
// implementation — if someone "optimises" the shifts, this disagrees.
function SessionPackEncoding(entryCms as Number, exitCms as Number,
        minFlightS as Number) as Number {
    return entryCms * 65536 + minFlightS * 2048 + exitCms;
}

(:test)
function turnsPageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = screenPx() / 2;
    var radius = screenPx() / 2.0 - BEZEL;

    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hHot = dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
    var hL = dc.getFontHeight(Graphics.FONT_LARGE);
    var hS = dc.getFontHeight(Graphics.FONT_SMALL);

    // row 0: header, widest with a wind axis set
    var header = "tack / jibe  NNE";
    var r = cornerRadius(dc.getTextWidthInPixels(header, Graphics.FONT_XTINY), hT,
        RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 0), cy);
    Test.assertMessage(r <= radius, "header corner " + r.format("%.0f") + " > " + radius);

    // row 1: the GIANT is now the last turn's score, not the tack/jibe count — the count is
    // a number you read once an hour, the score is the one that changes on every jibe. It is
    // fitted, so like every other fitted row in this suite it is asserted against fitRadius,
    // the margin the fitter itself works to.
    var pageR = RecordingView.fitRadius(dc, false, false);
    var y1 = RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 1);
    var scoreF = RecordingView.fitFont(dc, NUMBER_FONTS, 1, "100%",
        RecordingView.rowBudget(pageR, y1 - cy,
            RecordingView.inkH(dc, Graphics.FONT_NUMBER_HOT)));
    r = cornerRadius(dc.getTextWidthInPixels("100%", scoreF),
        RecordingView.inkH(dc, Graphics.FONT_NUMBER_HOT), y1, cy);
    Test.assertMessage(r <= pageR,
        "score corner " + r.format("%.0f") + " > " + pageR.toString());
    // ...and it must still be a NUMBER font: a score at FONT_LARGE is not a hero.
    Test.assertMessage(dc.getFontHeight(scoreF)
        >= dc.getFontHeight(Graphics.FONT_NUMBER_MILD),
        "turns giant shrank out of the number ladder");
    Test.assertEqual(RecordingView.scoreText(TurnDetector.OUTCOME_NONE, 0), "--");
    Test.assertEqual(RecordingView.scoreText(TurnDetector.OUTCOME_FLEW, 87), "87%");
    logger.debug("turns giant font height " + dc.getFontHeight(scoreF).toString()
        + " (NUMBER_HOT is " + hHot.toString() + "), corner " + r.format("%.0f") + " of "
        + pageR.toString());

    // row 2: the outcome SYMBOL next to the tack/jibe split. The symbol is a fixed box, so
    // this row's width does not depend on which outcome happens to be showing.
    var symW = RecordingView.outcomeSymSize(dc);
    Test.assertMessage(symW >= 14 && symW <= hL,
        "outcome symbol " + symW.toString() + "px out of band");
    r = cornerRadius(RecordingView.outcomeWidth(dc, symW, "99 / 99"), hL,
        RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 2), cy);
    Test.assertMessage(r <= radius, "split corner " + r.format("%.0f") + " > " + radius);
    // every outcome maps to a symbol, and the three real ones are all different
    Test.assertEqual(RecordingView.outcomeSymbol(TurnDetector.OUTCOME_FLEW), Glyphs.O_CHECK);
    Test.assertEqual(RecordingView.outcomeSymbol(TurnDetector.OUTCOME_TOUCHDOWN),
        Glyphs.O_TRIANGLE);
    Test.assertEqual(RecordingView.outcomeSymbol(TurnDetector.OUTCOME_FELL), Glyphs.O_CROSS);
    Test.assertEqual(RecordingView.outcomeSymbol(TurnDetector.OUTCOME_NONE), Glyphs.O_DASH);

    // row 3: three 2-digit tallies plus the session success rate that shares the row. The
    // widest this row ever gets is 3 x 2 digits and "100% ok", which is what it is asserted
    // at — it is the row most likely to run off a narrow fenix 7 glass.
    var y3ok = RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 3);
    var okBudget = RecordingView.rowBudget(pageR, y3ok - cy,
        RecordingView.inkH(dc, Graphics.FONT_SMALL));
    var tallyF = RecordingView.tallyFont(dc, "99", "99", "99", "100% ok", okBudget,
        TALLY_FLOOR);
    // THE rule this row exists to enforce: it never goes below FONT_SMALL. The old fitter
    // stepped the worst case (three two-digit tallies plus "100% ok") down to FONT_XTINY,
    // ~21 px of digit — and that worst case is a 30-turn session, i.e. exactly the tally the
    // rider wants to read. It sheds content instead now, and tallyContent says what survived.
    Test.assertEqual(tallyF, Graphics.FONT_SMALL);
    var worstMask = RecordingView.tallyContent(dc, "99", "99", "99", "100% ok", okBudget,
        tallyF);
    Test.assertMessage(worstMask >= 0,
        "not even three bare counts fit the tally row at FONT_SMALL");
    var worstOk = (worstMask & TALLY_OK) != 0 ? "100% ok" : "";
    var worstSep = (worstMask & TALLY_SEPARATORS) != 0 ? TURNS_TALLY_SEP : TALLY_SEP_NARROW;
    r = cornerRadius(
        RecordingView.tallyWidth(dc, "99", "99", "99", worstOk, worstSep, tallyF),
        RecordingView.inkH(dc, tallyF), y3ok, cy);
    Test.assertMessage(r <= pageR,
        "tally corner " + r.format("%.0f") + " > " + pageR.toString());
    // the ordinary case — one-digit tallies — keeps everything at the nominal font
    Test.assertEqual(RecordingView.tallyFont(dc, "9", "9", "9", "50% ok", okBudget,
        TALLY_FLOOR), Graphics.FONT_SMALL);
    Test.assertEqual(RecordingView.tallyContent(dc, "9", "9", "9", "50% ok", okBudget,
        Graphics.FONT_SMALL), TALLY_SEPARATORS | TALLY_OK);
    // ...and dropping content must actually be cheaper than keeping it, in that order
    Test.assertMessage(
        RecordingView.tallyWidth(dc, "99", "99", "99", "", TURNS_TALLY_SEP, tallyF)
            < RecordingView.tallyWidth(dc, "99", "99", "99", "100% ok", TURNS_TALLY_SEP,
                tallyF), "dropping the verdict must save width");
    Test.assertMessage(
        RecordingView.tallyWidth(dc, "99", "99", "99", "", TALLY_SEP_NARROW, tallyF)
            < RecordingView.tallyWidth(dc, "99", "99", "99", "", TURNS_TALLY_SEP, tallyF),
        "dropping the separators must save width");
    logger.debug("tally worst case at font height "
        + dc.getFontHeight(tallyF).toString() + " (SMALL is " + hS.toString()
        + "), content mask " + worstMask.toString());

    // the rate is a share of TURNS, not of outcomes, and it stays empty until there is one
    Test.assertEqual(RecordingView.okText(0, 0), "");
    Test.assertEqual(RecordingView.okText(2, 1), "50% ok");
    Test.assertEqual(RecordingView.okText(3, 3), "100% ok");
    Test.assertEqual(RecordingView.okText(30, 19), "63% ok");
    // ... and before the first turn the row is exactly the tally it always was
    Test.assertMessage(
        RecordingView.tallyWidth(dc, "9", "9", "9", "50% ok", TURNS_TALLY_SEP,
                Graphics.FONT_SMALL)
            > RecordingView.tallyWidth(dc, "9", "9", "9", "", TURNS_TALLY_SEP,
                Graphics.FONT_SMALL),
        "rate takes no room");

    // and the rows must not collide
    var y0 = RecordingView.turnsRowY(cy, hT, hHot, hL, hS, 0);
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
    var cy = screenPx() / 2;
    var radius = RecordingView.fitRadius(dc, true, false);
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
    var cx = screenPx() / 2;
    var cy = screenPx() / 2;
    var radius = RecordingView.fitRadius(dc, false, true);
    var limit = radius.toFloat();
    var hG = dc.getFontHeight(Graphics.FONT_NUMBER_MILD);
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hL = dc.getFontHeight(Graphics.FONT_LARGE);
    var bias = RecordingView.gridBias(dc);
    var inkL = RecordingView.inkH(dc, Graphics.FONT_LARGE);
    var inkT = RecordingView.inkH(dc, Graphics.FONT_XTINY);
    var narrowest = 9999;
    // the label row is now a glyph plus (optionally) the word, so it is measured as one block
    // and its height is whichever of the two is taller
    var gs = Glyphs.size(dc);
    var inkLbl = inkT > gs ? inkT : gs;

    for (var m = 1; m <= PageModel.M_MAX; m++) {
        var v = PageModel.worstValue(m);
        var lbl = PageModel.worstLabel(m);

        var yg = RecordingView.gridRowY(cy, hG, hT, hL, 0, true, bias);
        var inkG = RecordingView.inkH(dc, Graphics.FONT_NUMBER_MILD);
        var gf = RecordingView.fitGiant(dc, v, 3,
            RecordingView.rowBudget(radius, yg - cy, inkG));
        // measured at the font actually chosen: the band stays MILD-high whatever lands in
        // it, but the INK the glass clips is the ink of the font that gets drawn
        var r = cornerRadius(dc.getTextWidthInPixels(v, gf), RecordingView.inkH(dc, gf), yg, cy);
        Test.assertMessage(r <= limit,
            "grid giant m" + m.toString() + " r=" + r.format("%.0f") + " > " + limit);
        // ...and it must never fall past the readability floor: FONT_LARGE is the last rung
        // the overflow ladder may use for a giant.
        Test.assertMessage(dc.getFontHeight(gf) >= dc.getFontHeight(Graphics.FONT_LARGE),
            "grid giant m" + m.toString() + " fell to a label font");

        for (var row = 1; row <= 2; row++) {
            var yl = RecordingView.gridRowY(cy, hG, hT, hL, row, true, bias);
            var yv = yl + (hT + hL) / 2;
            var col = RecordingView.cellColumns(radius, yv - cy, inkL);
            var vf = RecordingView.fitFont(dc, TEXT_FONTS, 0, v, 2 * col[1]);
            if (2 * col[1] < narrowest) { narrowest = 2 * col[1]; }

            r = cornerRadiusAt(cx, cx + col[0],
                RecordingView.cellLabelWidth(dc, m, gs, lbl), inkLbl, yl, cy);
            Test.assertMessage(r <= limit, "grid label m" + m.toString() + " row"
                + row.toString() + " r=" + r.format("%.0f") + " > " + limit);
            // glyph-only mode must never be WIDER than the labelled one
            Test.assertMessage(RecordingView.cellLabelWidth(dc, m, gs, "")
                <= RecordingView.cellLabelWidth(dc, m, gs, lbl),
                "glyph-only label wider than the labelled one, m" + m.toString());
            // ... and the label block must stay inside its own column, or the two cells
            // would run into each other long before the glass clipped them
            Test.assertMessage(RecordingView.cellLabelWidth(dc, m, gs, lbl) <= 2 * col[1],
                "grid label m" + m.toString() + " row" + row.toString() + " is "
                    + RecordingView.cellLabelWidth(dc, m, gs, lbl).toString()
                    + "px in a " + (2 * col[1]).toString() + "px column");
            r = cornerRadiusAt(cx, cx + col[0], dc.getTextWidthInPixels(v, vf), inkL, yv, cy);
            Test.assertMessage(r <= limit, "grid value m" + m.toString() + " row"
                + row.toString() + " r=" + r.format("%.0f") + " > " + limit);
            // The over-stuffing canary, in two halves — because what costs this page its
            // width is the ARC, not the device.
            //
            // A plain GRID4 page must never drop a value below FONT_MEDIUM on any variant:
            // if it does, the page is carrying more than the circle holds and the answer is
            // fewer cells, not smaller digits.
            var plainCol = RecordingView.cellColumns(
                RecordingView.fitRadius(dc, false, false), yv - cy, inkL);
            var plainF = RecordingView.fitFont(dc, TEXT_FONTS, 0, v, 2 * plainCol[1]);
            Test.assertMessage(
                dc.getFontHeight(plainF) >= dc.getFontHeight(Graphics.FONT_MEDIUM),
                "grid value m" + m.toString() + " row" + row.toString()
                    + " shrank below FONT_MEDIUM with no arc on the page");

            // With the foil-% arc the floor is FONT_SMALL, and that is a finding rather than
            // a concession: a giant on top, a 2x2 under it and a ring of bezel arc round all
            // of it does not leave a six-character timer FONT_MEDIUM of chord in the bottom
            // row on a 416 px glass or narrower. FONT_SMALL is ~31 px of digit — at the
            // readability floor, not under it — and the alternative the old arc-blind fitter
            // chose was to draw the cell straight over the arc, which read as neither. The
            // arc is opt-in per page: it appears only where the rider put foil % on it.
            Test.assertMessage(dc.getFontHeight(vf) >= dc.getFontHeight(Graphics.FONT_SMALL),
                "grid value m" + m.toString() + " row" + row.toString()
                    + " shrank below FONT_SMALL even with the arc");
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

    var g1 = RecordingView.gridRowY(cy, hG, hT, hL, 1, true, bias);
    var g2 = RecordingView.gridRowY(cy, hG, hT, hL, 2, true, bias);
    Test.assertMessage(g2 - g1 >= hT + hL, "grid cell rows overlap");
    // without a giant the 2x2 centres on the screen instead of hanging under one
    Test.assertMessage(RecordingView.gridRowY(cy, hG, hT, hL, 1, false, bias) < g1,
        "grid without a giant recentres");
    // ... and it centres exactly: the block's top edge and bottom edge are equidistant
    var topEdge = RecordingView.gridRowY(cy, hG, hT, hL, 1, false, bias) - hT / 2;
    var botEdge = RecordingView.gridRowY(cy, hG, hT, hL, 2, false, bias) + (hT + hL) / 2 + hL / 2;
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
    var cy = screenPx() / 2;
    var radius = RecordingView.fitRadius(dc, false, false);
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
    var cx = screenPx() / 2;
    var cy = screenPx() / 2;
    var radius = screenPx() / 2 - TL_MARGIN;
    var limit = screenPx() / 2.0 - BEZEL;
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);

    // bands, in draw order, must stack without overlapping and stay inside the glass.
    // Band heights come from the device, not from the 454 px reference: a fenix 7S stacks
    // 23 + 50 where a fenix 8 stacks 44 + 96.
    var strip = RecordingView.stripH(dc);
    var spark = RecordingView.sparkH(dc);
    var yStripTop = RecordingView.timelineRowY(cy, hT, strip, spark, 1);
    var ySparkTop = RecordingView.timelineRowY(cy, hT, strip, spark, 3);
    var yDots = RecordingView.timelineRowY(cy, hT, strip, spark, 5);
    Test.assertMessage(ySparkTop >= yStripTop + strip + hT, "strip/spark overlap");
    Test.assertMessage(yDots - TL_DOT_R >= ySparkTop + spark + hT, "spark/dots overlap");

    var hwStrip = RecordingView.bandHalfWidth(radius, yStripTop, yStripTop + strip, cy);
    var hwSpark = RecordingView.bandHalfWidth(radius, ySparkTop, ySparkTop + spark, cy);
    var hwDots = RecordingView.bandHalfWidth(radius, yDots - TL_DOT_R, yDots + TL_DOT_R, cy);
    // "wide enough to be worth drawing", as a fraction of the glass rather than an absolute:
    // 22 % of the width is what the old 100 px floor meant on a 454 px fenix 8.
    var narrow = screenPx() * 22 / 100;
    Test.assertMessage(hwStrip > narrow && hwSpark > narrow && hwDots > narrow,
        "timeline bands too narrow: " + hwStrip.toString() + "/" + hwSpark.toString()
            + "/" + hwDots.toString() + " (floor " + narrow.toString() + ")");

    // deepest corner of each band
    var r = cornerRadiusAt(cx, cx, 2 * hwStrip, strip, yStripTop + strip / 2, cy);
    Test.assertMessage(r <= limit, "strip corner " + r.format("%.0f") + " > " + limit);
    r = cornerRadiusAt(cx, cx, 2 * hwSpark, spark, ySparkTop + spark / 2, cy);
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

    // 256 slots must each get at least one pixel column wherever the glass is wide enough to
    // hold them. A 240-280 px fenix 7 physically cannot, and drawTimelinePage degrades by
    // mapping several slots onto the same column (barW clamped to 1) rather than dropping
    // them — so there the requirement is only that the strip still spans most of the glass.
    if (2 * hwStrip >= 256) {
        Test.assertMessage(true, "");
    } else {
        Test.assertMessage(2 * hwStrip >= screenPx() * 60 / 100,
            "strip only " + (2 * hwStrip).toString() + "px of a "
                + screenPx().toString() + "px glass");
        logger.debug("glass too narrow for 256 slots — " + (2 * hwStrip).toString()
            + "px strip shares columns");
    }
    logger.debug("timeline strip " + (2 * hwStrip).toString() + "px spark "
        + (2 * hwSpark).toString() + "px dots " + shown.toString() + " of 64");
    return true;
}

// One START-page text row: it must fit the glass at the font the page will pick, and it must
// still be the nominal font — a shrink means the layout gave the row less room than it needs.
function assertStartRow(dc as Graphics.Dc, text as String, y as Number, cy as Number,
        radius as Number, from as Number, ink as Number) as Void {
    var f = RecordingView.fitFont(dc, TEXT_FONTS, from, text,
        RecordingView.rowBudget(radius, y - cy, ink));
    var r = cornerRadius(dc.getTextWidthInPixels(text, f), ink, y, cy);
    Test.assertMessage(r <= radius.toFloat(),
        "start row '" + text + "' r=" + r.format("%.0f") + " > " + radius.toString());
    Test.assertEqual(f, TEXT_FONTS[from]);
}

// START page: title, GPS dot row, GPS state, hint. It is the first thing every tester sees,
// and it was the last page still laid out in absolute pixels — offsets authored on a 454 px
// AMOLED that overflowed a 240 px fenix 7S. Same measurement as the recording pages.
(:test)
function startPageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cx = screenPx() / 2;
    var cy = screenPx() / 2;
    var radius = RecordingView.fitRadius(dc, false, false);
    var limit = radius.toFloat();
    var titleFont = TEXT_FONTS[START_TITLE_FONT];
    var bodyFont = TEXT_FONTS[START_BODY_FONT];
    var hTitle = dc.getFontHeight(titleFont);
    var hBody = dc.getFontHeight(bodyFont);
    var inkTitle = RecordingView.inkH(dc, titleFont);
    var inkBody = RecordingView.inkH(dc, bodyFont);
    var r = StartView.dotRadius(dc);
    var step = StartView.dotStep(r);
    var hDots = 2 * r;

    var yTitle = StartView.rowY(cy, hTitle, hDots, hBody, 0);
    var yDots = StartView.rowY(cy, hTitle, hDots, hBody, 1);
    var yState = StartView.rowY(cy, hTitle, hDots, hBody, 2);
    var yHint = StartView.rowY(cy, hTitle, hDots, hBody, 3);

    // rows in order, no overlap
    Test.assertMessage(yDots - yTitle >= (hTitle + hDots) / 2, "title/dots overlap");
    Test.assertMessage(yState - yDots >= (hDots + hBody) / 2, "dots/state overlap");
    Test.assertMessage(yHint - yState >= hBody, "state/hint overlap");

    // the block is centred: equal air above the title and below the hint
    Test.assertMessage((((cy - (yTitle - hTitle / 2)) - ((yHint + hBody / 2) - cy)).abs() <= 1),
        "start block off centre: " + (cy - (yTitle - hTitle / 2)).toString() + " vs "
            + ((yHint + hBody / 2) - cy).toString());

    // every row inside the glass, at the font the page will actually pick
    assertStartRow(dc, START_TITLE, yTitle, cy, radius, START_TITLE_FONT, inkTitle);
    assertStartRow(dc, "GPS ready", yState, cy, radius, START_BODY_FONT, inkBody);
    assertStartRow(dc, START_HINT, yHint, cy, radius, START_BODY_FONT, inkBody);

    // the four dots, measured at the outermost one
    var xOuter = cx + (3 * step) / 2;
    var cr = cornerRadiusAt(cx, xOuter, hDots, hDots, yDots, cy);
    Test.assertMessage(cr <= limit, "start dots r=" + cr.format("%.0f") + " > " + limit);
    Test.assertMessage(step >= 2 * r + 2, "dots touch: step " + step.toString()
        + " for r " + r.toString());
    logger.debug("start: dots r" + r.toString() + " step " + step.toString()
        + ", rows " + yTitle.toString() + "/" + yDots.toString() + "/" + yState.toString()
        + "/" + yHint.toString() + " on " + screenPx().toString() + "px");
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

// ---- Glyphs, bezel arc, celebration ----

// Every metric that lands in a cell must have a glyph, every glyph must be one the renderer
// knows how to draw, and drawing all of them must not throw on the device's real Dc.
(:test)
function everyMetricHasADrawableGlyph(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var s = Glyphs.size(dc);
    Test.assertMessage(s >= Glyphs.MIN_PX && s <= Glyphs.MAX_PX,
        "glyph size " + s.toString() + " outside the " + Glyphs.MIN_PX.toString() + "-"
            + Glyphs.MAX_PX.toString() + " band");

    var seen = 0;
    for (var m = 1; m <= PageModel.M_MAX; m++) {
        var g = PageModel.glyph(m);
        Test.assertMessage(g != Glyphs.G_NONE,
            "metric " + m.toString() + " has no glyph");
        Test.assertMessage(g >= Glyphs.G_WING && g <= Glyphs.G_BATTERY,
            "metric " + m.toString() + " maps to unknown glyph " + g.toString());
        if (g > seen) { seen = g; }
        // painting it must be safe at the smallest and largest size the band allows
        Glyphs.draw(dc, g, 40, 40, Glyphs.MIN_PX, Graphics.COLOR_LT_GRAY);
        Glyphs.draw(dc, g, 80, 40, Glyphs.MAX_PX, Graphics.COLOR_LT_GRAY);
    }
    Test.assertEqual(PageModel.glyph(PageModel.M_NONE), Glyphs.G_NONE);
    Test.assertEqual(seen, Glyphs.G_BATTERY);   // no glyph in the catalog is dead code

    // and the outcome symbols, including the triangle's polygon scratch reused twice
    for (var o = Glyphs.O_DASH; o <= Glyphs.O_CROSS; o++) {
        Glyphs.drawOutcome(dc, o, 60, 100, 24, Graphics.COLOR_GREEN);
        Glyphs.drawOutcome(dc, o, 60, 140, 18, Graphics.COLOR_RED);
    }
    logger.debug("glyphs: " + Glyphs.G_BATTERY.toString() + " metric symbols + 4 outcomes at "
        + s.toString() + "px");
    return true;
}

// The foil-% bezel arc: 12 o'clock start, clockwise sweep, and only on pages that ask for it.
(:test)
function foilBezelArcSweepsClockwiseFromTwelve(logger as Test.Logger) as Boolean {
    // Garmin angles run counter-clockwise from 3 o'clock, so a clockwise sweep SUBTRACTS
    Test.assertEqual(RecordingView.bezelEndDeg(0), 90);        // no sweep: still at 12
    Test.assertEqual(RecordingView.bezelEndDeg(25), 0);        // quarter: 3 o'clock
    Test.assertEqual(RecordingView.bezelEndDeg(50), 270);      // half: 6 o'clock
    Test.assertEqual(RecordingView.bezelEndDeg(75), 180);      // three quarters: 9 o'clock
    // never negative, never out of range, for any percentage the engine can produce
    for (var p = 0; p <= 100; p++) {
        var d = RecordingView.bezelEndDeg(p);
        Test.assertMessage(d >= 0 && d < 360, "bezel end " + d.toString() + " at " + p.toString());
    }

    // the arc rides inside the glass, clear of the text margin
    var dc = testDc();
    var pen = RecordingView.bezelPen(dc);
    var r = dc.getWidth() / 2 - RecordingView.bezelInset(dc) - pen / 2;
    Test.assertMessage(r + pen / 2 <= dc.getWidth() / 2 - FIT_MARGIN,
        "bezel arc outer edge crosses the fit margin");
    // The decorations are FRACTIONS of the radius, not pixel counts: a ring that keeps its
    // 454-authored 10 px on a 260 px glass eats nearly twice the share of the width, on the
    // glass with the least to give. Scaled, every variant spends the same proportion.
    Test.assertMessage(RecordingView.ringPen(dc, false) >= 1
        && RecordingView.ringInset(dc, false) >= 1, "scaled bezel dims must stay drawable");
    Test.assertMessage(RecordingView.ringInset(dc, true) > RecordingView.ringInset(dc, false),
        "the nested ring must step further in than the plain one");
    Test.assertMessage(RecordingView.scaled(dc, RING_PEN) * REF_PX
        <= (RING_PEN + 1) * dc.getWidth(), "ring pen is not a proportion of the glass");

    // it is a property of the page, not of a cell: the shipped Session grid has foil %
    PageModel.build({});
    Test.assertMessage(PageModel.pageHasMetric(1, PageModel.M_FOIL_PCT),
        "default grid page must carry the foil arc");
    Test.assertMessage(!PageModel.pageHasMetric(0, PageModel.M_FOIL_PCT),
        "default speed hero has no foil % and so no arc");
    Test.assertMessage(!PageModel.pageHasMetric(2, PageModel.M_FOIL_PCT), "records page");
    logger.debug("bezel arc r=" + r.toString() + "px, pen " + BEZEL_PEN.toString());
    return true;
}

// The PB celebration walks a fixed number of frames and clears itself.
(:test)
function pbFlashPulsesThenClears(logger as Test.Logger) as Boolean {
    Test.assertMessage(!PbFlash.active(), "idle at rest");
    PbFlash.fire(12.5);
    Test.assertMessage(PbFlash.active(), "a PB starts the flash");
    Test.assertEqual(PbFlash.best2sMps, 12.5);
    // A record is an EFFORT event, not a verdict — so the celebration is the effort window's
    // orange and NOT the outcome ladder's green, which on this app means "that jibe flew
    // through" (docs/presentation.md).
    Test.assertEqual(PbFlash.color(), Ink.effortWindow());
    Test.assertMessage(PbFlash.color() != Ink.ladderFlew(),
        "the PB flash must not wear the outcome ladder's green");

    // the shade alternates — that is what makes it a pulse rather than a still card — and the
    // dim frame is the SAME token at half brightness, not a second colour
    PbFlash.tick();
    var dim = PbFlash.color();
    Test.assertMessage(dim != Ink.effortWindow(), "the pulse must actually alternate");
    Test.assertEqual(dim, (Ink.effortWindow() >> 1) & 0x7F7F7F);
    PbFlash.tick();
    Test.assertEqual(PbFlash.color(), Ink.effortWindow());

    // and it always runs out, even if nothing ever calls stop()
    for (var i = 0; i < PbFlash.FRAMES; i++) {
        PbFlash.tick();
    }
    Test.assertMessage(!PbFlash.active(), "the flash must clear itself");
    PbFlash.tick();                          // ticking an idle flash is harmless
    Test.assertMessage(!PbFlash.active(), "idle stays idle");

    // the overlay's three rows are stacked from font heights and must clear the glass at
    // the fastest speed the display can produce
    var dc = testDc();
    var cy = screenPx() / 2;
    var limit = RecordingView.fitRadius(dc, false, false).toFloat();
    var hHot = dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
    var hS = dc.getFontHeight(Graphics.FONT_SMALL);
    var r = cornerRadius(dc.getTextWidthInPixels("99.9", Graphics.FONT_NUMBER_HOT),
        RecordingView.inkH(dc, Graphics.FONT_NUMBER_HOT),
        cy - (hHot + hS) / 2 + hS + hHot / 2, cy);
    Test.assertMessage(r <= limit, "PB number corner " + r.format("%.0f") + " > " + limit);
    r = cornerRadius(dc.getTextWidthInPixels("NEW PB", Graphics.FONT_SMALL),
        RecordingView.inkH(dc, Graphics.FONT_SMALL), cy - (hHot + hS) / 2 + hS / 2, cy);
    Test.assertMessage(r <= limit, "PB header corner " + r.format("%.0f") + " > " + limit);
    r = cornerRadius(dc.getTextWidthInPixels("km/h", Graphics.FONT_SMALL),
        RecordingView.inkH(dc, Graphics.FONT_SMALL), cy + (hHot + hS) / 2 + hS / 2, cy);
    Test.assertMessage(r <= limit, "PB unit corner " + r.format("%.0f") + " > " + limit);

    PbFlash.fire(13.0);
    PbFlash.stop();
    Test.assertMessage(!PbFlash.active(), "stop() clears it");
    Test.assertMessage(PbFlash.FRAMES * PbFlash.FRAME_MS >= 500
        && PbFlash.FRAMES * PbFlash.FRAME_MS <= 1000,
        "celebration length " + (PbFlash.FRAMES * PbFlash.FRAME_MS).toString() + " ms");
    logger.debug("PB flash: " + PbFlash.FRAMES.toString() + " frames x "
        + PbFlash.FRAME_MS.toString() + " ms");
    return true;
}

// ---- Map trail tinting ----
// One MapPolyline per run of equal foil state, with the run count bounded so a chopped-up
// session cannot ask the map for a hundred lines.
(:test)
function trackTintBoundsTheNumberOfPolylines(logger as Test.Logger) as Boolean {
    // a clean two-flight track: off, flying, off, flying, off
    var fly = new [40] as Array<Boolean>;
    for (var i = 0; i < 40; i++) {
        fly[i] = (i / 8) % 2 == 1;
    }
    Test.assertEqual(TrackTint.minRunFor(fly, 40), 1);       // 5 runs, no merging needed
    Test.assertEqual(TrackTint.runCount(fly, 40, 1), 5);
    Test.assertEqual(TrackTint.runEnd(fly, 40, 0, 1), 8);
    Test.assertEqual(TrackTint.runEnd(fly, 40, 8, 1), 16);
    Test.assertEqual(TrackTint.runEnd(fly, 40, 32, 1), 40);  // the last run ends at n

    // the pathological case the bound exists for: state flips on every single point
    var noisy = new [128] as Array<Boolean>;
    for (var i = 0; i < 128; i++) {
        noisy[i] = i % 2 == 0;
    }
    Test.assertEqual(TrackTint.runCount(noisy, 128, 1), 128);
    var minRun = TrackTint.minRunFor(noisy, 128);
    Test.assertMessage(minRun > 1, "flicker must be merged away");
    var runs = TrackTint.runCount(noisy, 128, minRun);
    Test.assertMessage(runs <= TrackTint.MAX_RUNS,
        runs.toString() + " runs > the " + TrackTint.MAX_RUNS.toString() + " cap");

    // merging absorbs a short flicker into the run around it rather than splitting it
    var blip = new [10] as Array<Boolean>;
    for (var i = 0; i < 10; i++) {
        blip[i] = true;
    }
    blip[5] = false;
    Test.assertEqual(TrackTint.runCount(blip, 10, 1), 3);
    Test.assertEqual(TrackTint.runCount(blip, 10, 2), 1);
    Test.assertEqual(TrackTint.runEnd(blip, 10, 0, 2), 10);

    // every run must be non-empty and they must tile the track exactly, at any minRun
    for (var m = 1; m <= 8; m++) {
        var i = 0;
        var guard = 0;
        while (i < 128 && guard < 200) {
            var end = TrackTint.runEnd(noisy, 128, i, m);
            Test.assertMessage(end > i, "empty run at " + i.toString());
            i = end;
            guard++;
        }
        Test.assertEqual(i, 128);
    }
    logger.debug("track tint: 128 alternating points collapse to " + runs.toString()
        + " polylines at minRun " + minRun.toString());
    return true;
}

// ---- Page model ----

// The out-of-the-box page set must be byte-for-byte the five screens the app shipped with.
(:test)
function pageModelDefaultsMatchShippedPages(logger as Test.Logger) as Boolean {
    PageModel.build({});
    Test.assertMessage(PageModel.count() == 6,
        "expected 6 default pages, got " + PageModel.count().toString());

    // Page 1 is the bespoke main screen since 0.8.0. It carries NO slots — what it shows is
    // the point of the screen — and the flight timer and heart rate that used to live here
    // are catalog metrics the rider can put in any slot on any other page.
    Test.assertEqual(PageModel.layoutAt(0), PageModel.LAYOUT_MAIN);
    for (var s = 0; s < PageModel.SLOTS; s++) {
        Test.assertEqual(PageModel.slotAt(0, s), PageModel.M_NONE);
    }

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

    // TIMELINE ships ON (page 6): it is the page that shows the session as a story, and a
    // tester who has to find it in Garmin Connect never sees it.
    Test.assertEqual(PageModel.layoutAt(5), PageModel.LAYOUT_TIMELINE);

    // the cell labels the shipped Session page used, straight from the catalog
    Test.assertEqual(PageModel.label(PageModel.M_FOIL_TIME), "foil");
    Test.assertEqual(PageModel.label(PageModel.M_LONGEST), "longest");
    Test.assertEqual(PageModel.label(PageModel.M_DISTANCE), "km");
    Test.assertEqual(PageModel.label(PageModel.M_FLIGHTS), "flights");
    Test.assertEqual(PageModel.label(PageModel.M_TIMER), "timer");
    Test.assertEqual(PageModel.suffix(PageModel.M_HR), " bpm");

    // wrapping is total: no index can escape the page set
    Test.assertEqual(PageModel.wrap(-1), 5);
    Test.assertEqual(PageModel.wrap(6), 0);
    Test.assertMessage(!PageModel.mapPage, "map off by default");
    logger.debug("defaults: 6 pages, main/grid4/records/turns/clock/timeline");
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

// ---- Pump / takeoff detection ----
// The headless twin of lab/tests/test_pump.py: the same synthetic wrist traces, driven
// through the real PumpDetector at the real 25 Hz grid. Every expected count below was first
// produced by the lab implementation on the identical signal (docs/algorithms.md "Watch
// approximation"), so a divergence here means the port drifted, not that the numbers moved.

// One second of synthetic wrist motion per call, pushed as the ~25-sample batch a
// SensorData callback delivers, followed by the 1 Hz context tick MetricsEngine makes.
class PumpRig {
    var det as PumpDetector;
    var ms as Number = 100000;      // a System.getTimer()-like clock
    var flying as Boolean = false;
    var turnOpen as Boolean = false;
    var lastEvent as Number = 0;

    hidden var _t as Float = 0.0;   // seconds of signal generated so far
    hidden var _buf as Array<Float>;

    function initialize() {
        det = new PumpDetector(new WingFoilCore.Config());
        det.start(25);
        _buf = new [25] as Array<Float>;
    }

    // |a| = 1 g (a still wrist) + amp*sin(2*pi*f*t) + amp2*sin(2*pi*f2*t + phase2)
    function run(seconds as Number, f as Float, amp as Float,
            f2 as Float, amp2 as Float, phase2 as Float) as Void {
        for (var s = 0; s < seconds; s++) {
            for (var i = 0; i < 25; i++) {
                var t = _t + i / 25.0;
                var v = 1.0 + amp * Math.sin(2.0 * Math.PI * f * t);
                if (amp2 != 0.0) {
                    v += amp2 * Math.sin(2.0 * Math.PI * f2 * t + phase2);
                }
                _buf[i] = v;
            }
            _t += 1.0;
            ms += 1000;
            det.pushMagBatch(_buf, ms);
            lastEvent = det.tick(ms, flying, turnOpen, FlightDetector.EVENT_NONE);
        }
    }

    function pump(seconds as Number) as Void {
        run(seconds, 1.2, 0.6, 0.0, 0.0, 0.0);      // a real burst: ~1.2 Hz, 0.6 g
    }

    function quiet(seconds as Number) as Void {
        run(seconds, 1.0, 0.0, 0.0, 0.0, 0.0);
    }

    // The tick on which the FlightDetector confirms a flight (>= minFlight seconds in).
    function confirmFlight() as Number {
        ms += 1000;
        lastEvent = det.tick(ms, flying, turnOpen, FlightDetector.EVENT_START);
        return lastEvent;
    }
}

// A clean takeoff: pump, get up, flight confirmed. One attempt, one success, and the
// stroke count of the effort becomes pumps-to-takeoff.
(:test)
function pumpBurstBecomesATakeoffAttemptAndSucceeds(logger as Test.Logger) as Boolean {
    var r = new PumpRig();
    r.quiet(5);
    Test.assertEqual(r.det.strokes, 0);              // a still wrist is never pumping
    r.pump(10);                                       // 10 s at 1.2 Hz => ~12 strokes

    Test.assertMessage(r.det.strokes >= 10 && r.det.strokes <= 14,
        "10 s at 1.2 Hz gave " + r.det.strokes.toString() + " strokes, lab says 12");
    Test.assertMessage(r.det.minGapMs >= r.det.REFRACTORY_MS,
        "strokes " + r.det.minGapMs.toString() + " ms apart beat the refractory");
    Test.assertMessage(r.det.attemptOpen(), "a qualifying burst must open an effort");
    Test.assertMessage(r.det.cadence >= 40 && r.det.cadence <= 110,
        "cadence " + r.det.cadence.toString() + " spm off a 72 spm burst");

    // up on the foil, then the flight is confirmed a few seconds later
    r.flying = true;
    r.quiet(3);
    var burst = r.det.strokes;
    Test.assertEqual(r.confirmFlight(), PumpDetector.EVENT_TAKEOFF);

    Test.assertEqual(r.det.successes, 1);
    Test.assertEqual(r.det.failed, 0);
    Test.assertEqual(r.det.attempts(), 1);
    Test.assertEqual(r.det.successPct(), 100);
    Test.assertMessage(r.det.lastPumpsToTakeoff >= 8
        && r.det.lastPumpsToTakeoff <= burst,
        "pumps to takeoff " + r.det.lastPumpsToTakeoff.toString()
            + " out of " + burst.toString() + " strokes");
    Test.assertEqual(r.det.avgPumpsX10(), r.det.lastPumpsToTakeoff * 10);
    Test.assertMessage(r.det.lastPumpsToTakeoff >= r.det.FREE_TAKEOFF,
        "a pumped takeoff is not a free one");
    logger.debug("takeoff: " + burst.toString() + " strokes, "
        + r.det.lastPumpsToTakeoff.toString() + " of them in the run");
    return true;
}

// Chop is faster and a lean is slower than pumping; wing trim is in band but tiny. None of
// the three may produce a single stroke (lab test_chop_is_rejected / small_wing_trim).
(:test)
function chopAndWobbleAreNotPumping(logger as Test.Logger) as Boolean {
    var r = new PumpRig();
    r.run(20, 6.0, 0.5, 0.1, 1.0, 0.0);      // 6 Hz chop over a 0.1 Hz body lean
    Test.assertMessage(r.det.strokes == 0,
        "chop + lean produced " + r.det.strokes.toString() + " strokes");
    r.run(20, 1.2, 0.06, 0.0, 0.0, 0.0);     // in band, far below pumpStrokeAmp
    Test.assertMessage(r.det.strokes == 0,
        "wing-trim wobble produced " + r.det.strokes.toString() + " strokes");
    Test.assertEqual(r.det.attempts(), 0);
    Test.assertEqual(r.det.cadence, 0);
    logger.debug("chop (6 Hz), lean (0.1 Hz) and a 0.06 g wobble all rejected");
    return true;
}

// A double-humped stroke (1.2 Hz + its 2.4 Hz overtone) puts local maxima ~0.2 s apart. The
// refractory must swallow the second hump: no human pumps at more than 2.5 strokes/s.
(:test)
function refractoryDeadTimeIsEnforced(logger as Test.Logger) as Boolean {
    var r = new PumpRig();
    r.quiet(3);
    r.run(20, 1.2, 0.6, 2.4, 0.5, 1.5);
    Test.assertMessage(r.det.strokes > 12,
        "a 20 s two-tone burst is pumping, got " + r.det.strokes.toString());
    Test.assertMessage(r.det.minGapMs >= r.det.REFRACTORY_MS,
        "two strokes " + r.det.minGapMs.toString() + " ms apart");
    // the raw peak train carries ~48 candidates (the 2.4 Hz hump); the dead time must eat
    // most of them, so the surviving cadence stays physically possible
    Test.assertMessage(r.det.refractoryDrops > 10,
        "the dead time swallowed only " + r.det.refractoryDrops.toString() + " peaks");
    Test.assertMessage(r.det.strokes <= 30,
        "impossible cadence: " + r.det.strokes.toString() + " strokes in 20 s");
    logger.debug("two-tone burst: " + r.det.strokes.toString() + " strokes kept, "
        + r.det.refractoryDrops.toString() + " dropped by the dead time, closest pair "
        + r.det.minGapMs.toString() + " ms");
    return true;
}

// Pumping to hold a glide is not a takeoff attempt — it is counted, separately, and never
// opens an effort (lab: the `in_flight` episode class).
(:test)
function inFlightPumpingIsNotATakeoffAttempt(logger as Test.Logger) as Boolean {
    var r = new PumpRig();
    r.flying = true;
    r.quiet(5);
    r.pump(10);
    r.quiet(12);                                  // past takeoffAttemptWindow
    Test.assertMessage(r.det.strokes >= 10, "in-flight strokes must still be counted");
    Test.assertEqual(r.det.inFlightStrokes, r.det.strokes);
    Test.assertMessage(!r.det.attemptOpen(), "no effort may be open while flying");
    Test.assertEqual(r.det.attempts(), 0);
    Test.assertEqual(r.det.failed, 0);
    logger.debug("in-flight: " + r.det.strokes.toString()
        + " strokes, 0 attempts");
    return true;
}

// Pumping the foil back after a jibe touchdown belongs to that turn, which already scored
// it — counting it again as a failed takeoff would double-charge the same mistake.
(:test)
function turnRecoveryBurstIsNotAFailedAttempt(logger as Test.Logger) as Boolean {
    var r = new PumpRig();
    r.quiet(5);
    r.turnOpen = true;                            // a TurnDetector outcome window is running
    r.pump(10);
    r.turnOpen = false;
    r.quiet(12);
    Test.assertMessage(r.det.strokes >= 10, "recovery strokes are still strokes");
    Test.assertEqual(r.det.recoveryEpisodes, 1);
    Test.assertEqual(r.det.failed, 0);
    Test.assertEqual(r.det.attempts(), 0);
    logger.debug("recovery burst owned by the turn: 0 attempts, "
        + r.det.strokes.toString() + " strokes");
    return true;
}

// The other half of the differentiator: he pumped and did NOT get up. Also the FIT packing —
// every session field must survive its uint8/uint16 and read 0 when nothing happened.
(:test)
function failedAttemptExpiresAndFitPackingIsSane(logger as Test.Logger) as Boolean {
    var r = new PumpRig();
    r.quiet(5);
    r.pump(10);
    Test.assertMessage(r.det.attemptOpen(), "effort open while pumping");
    r.quiet(5);
    Test.assertMessage(r.det.attemptOpen(),
        "an effort stays open for takeoffAttemptWindow past the last stroke");
    r.quiet(8);
    Test.assertMessage(!r.det.attemptOpen(), "10 s of silence closes the effort");
    Test.assertEqual(r.det.failed, 1);
    Test.assertEqual(r.det.successes, 0);
    Test.assertEqual(r.det.attempts(), 1);
    Test.assertEqual(r.det.successPct(), 0);
    Test.assertEqual(r.det.avgPumpsX10(), 0);     // no takeoff: nothing to average
    Test.assertEqual(r.det.cadence, 0);           // silence reads 0 spm, not stale

    // FIT session 35-38 packing (docs/fit-schema.md)
    Test.assertMessage(r.det.attempts() <= 254 && r.det.successes <= 254,
        "uint8 session counters");
    Test.assertMessage(r.det.strokes < 65535, "uint16 total_pump_strokes");
    // pump_cadence is a uint8 the refractory bounds at 150 spm
    Test.assertMessage(r.det.cadence <= 254, "uint8 pump_cadence");

    // a GPS gap drops an unjudgeable effort rather than calling it a failure (lab: `unknown`)
    r.pump(10);
    Test.assertMessage(r.det.attemptOpen(), "second effort open");
    r.det.onGap();
    r.quiet(12);
    Test.assertEqual(r.det.failed, 1);
    logger.debug("failed attempt counted once; a gap drops the effort as unknown");
    return true;
}

// ---- Takeoff HR cost ----
// The watch slice of lab/src/wingfoil_lab/hrcost.py (docs/algorithms.md "HR cost"). The
// tracker is driven here at the 1 Hz it sees on the water, with the heart rates an optical
// sensor under a wetsuit sleeve actually produces — including the ones it does not produce.

// `seconds` of 1 Hz samples at one heart rate and one effort state. `hr` null = the sensor
// has lost the wrist, which on the water is a normal minute, not an error.
function hrCostHold(t as HrCostTracker, seconds as Number, hr as Number?,
        effortOpen as Boolean) as Void {
    for (var i = 0; i < seconds; i++) {
        t.tick(1.0, hr, effortOpen, false);
    }
}

// A clean takeoff, priced. The load-bearing part is the timing: the number appears when the
// 30 s window closes, not when he gets up, because that is where the heart rate the pumping
// produced actually shows up.
(:test)
function hrCostPricesATakeoffWhenThePeakHasArrived(logger as Test.Logger) as Boolean {
    // the constants are the lab's, mirrored not re-invented
    Test.assertEqual(HR_COST_PEAK_WINDOW_S, 30.0);
    Test.assertEqual(HR_COST_MIN_RISE_BPM, 5);
    Test.assertEqual(HR_COST_MIN_BPM, 30);
    Test.assertEqual(HR_COST_MAX_BPM, 220);

    var t = new HrCostTracker();
    Test.assertEqual(t.lastCostBpm, -1);
    hrCostHold(t, 20, 96, false);                // drifting about, not pumping
    Test.assertEqual(t.lastCostBpm, -1);
    Test.assertMessage(!t.windowOpen(), "no effort, no window");

    t.tick(1.0, 100, true, false);               // first stroke: the anchor, at 100 bpm
    Test.assertMessage(t.windowOpen(), "the start of the effort anchors the window");
    hrCostHold(t, 7, 104, true);
    t.tick(1.0, 108, true, true);                // 9 s in: up, flight confirmed
    Test.assertMessage(t.lastCostBpm < 0, "nothing published while the heart is still rising");

    hrCostHold(t, 10, 118, false);               // the peak lands ~20 s after the anchor
    hrCostHold(t, 9, 112, false);                // and comes back down
    Test.assertMessage(t.windowOpen(), "the window runs the full 30 s past the anchor");
    Test.assertEqual(t.lastCostBpm, -1);
    hrCostHold(t, 2, 110, false);                // 30 s: the window closes
    Test.assertMessage(!t.windowOpen(), "the window closes on its own");
    Test.assertEqual(t.lastCostBpm, 118 - 100);

    // the next takeoff replaces the last: this metric is "the one you just did", not a session
    hrCostHold(t, 60, 108, false);
    Test.assertEqual(t.lastCostBpm, 18);
    t.tick(1.0, 105, true, false);
    hrCostHold(t, 4, 112, true);
    t.tick(1.0, 116, true, true);
    hrCostHold(t, 30, 130, false);
    Test.assertEqual(t.lastCostBpm, 130 - 105);

    // and the catalog dashes it until there is one, the way every unavailable metric does
    var c = getApp().controller;
    var saved = c.engine;
    c.engine = new MetricsEngine();
    Test.assertEqual(PageModel.value(PageModel.M_TAKEOFF_COST, c), "--");
    c.engine.hrCost.lastCostBpm = 12;
    Test.assertEqual(PageModel.value(PageModel.M_TAKEOFF_COST, c), "12");
    Test.assertEqual(PageModel.suffix(PageModel.M_TAKEOFF_COST), " bpm");
    Test.assertEqual(PageModel.label(PageModel.M_TAKEOFF_COST), "hr cost");
    c.engine = saved;
    logger.debug("takeoff cost: 18 bpm at the window close, then 25 for the next takeoff");
    return true;
}

// Every way the number must NOT appear. A confident wrong figure is worse than a dash, and
// on a wrist in cold water the wrong figure is the likelier one.
(:test)
function hrCostRefusesToGuess(logger as Test.Logger) as Boolean {
    var t = new HrCostTracker();

    // a rise under hrMinRise is sensor noise wearing a takeoff's clothes
    t.tick(1.0, 100, true, false);
    hrCostHold(t, 4, 101, true);
    t.tick(1.0, 102, true, true);
    hrCostHold(t, 40, 103, false);
    Test.assertMessage(!t.windowOpen(), "the window closed");
    Test.assertEqual(t.lastCostBpm, -1);

    // a FAILED attempt: he pumped, his heart paid for it, he never got up. No takeoff, no
    // takeoff cost — the effort is the phone's `failed` episode, counted nowhere here.
    t.tick(1.0, 100, true, false);
    hrCostHold(t, 15, 130, true);
    hrCostHold(t, 20, 130, false);
    Test.assertEqual(t.lastCostBpm, -1);

    // the sensor drops out mid-window. What survives still carries a peak, and a hole can
    // only hide a HIGHER one, so the cost is biased low — never high.
    t.tick(1.0, 100, true, false);
    hrCostHold(t, 3, 104, true);
    t.tick(1.0, 106, true, true);
    hrCostHold(t, 8, null, false);
    hrCostHold(t, 8, 121, false);
    hrCostHold(t, 10, null, false);
    Test.assertEqual(t.lastCostBpm, 121 - 100);

    // ...and what the sensor emits instead of nothing must never become the peak: 240 is not
    // a heart and 12 is a wrist that has stopped reading one.
    t.tick(1.0, 100, true, false);
    hrCostHold(t, 3, 104, true);
    t.tick(1.0, 108, true, true);
    hrCostHold(t, 5, 240, false);
    hrCostHold(t, 5, 12, false);
    hrCostHold(t, 20, 111, false);
    Test.assertEqual(t.lastCostBpm, 111 - 100);

    // no heart rate AT the anchor: there is no baseline to subtract from anything, so the
    // attempt is unmeasurable however cleanly it goes.
    var u = new HrCostTracker();
    u.tick(1.0, null, true, false);
    Test.assertMessage(!u.windowOpen(), "no baseline, no window");
    hrCostHold(u, 4, 140, true);
    u.tick(1.0, 150, true, true);
    hrCostHold(u, 40, 150, false);
    Test.assertEqual(u.lastCostBpm, -1);
    logger.debug("small rise, failed attempt, dropout, garbage bpm and a missing anchor all "
        + "leave the metric at a dash");
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
    var ref = Graphics.createBufferedBitmap({:width => screenPx(), :height => screenPx()});
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

    var layouts = [PageModel.LAYOUT_MAIN, PageModel.LAYOUT_HERO, PageModel.LAYOUT_GRID4,
        PageModel.LAYOUT_CELLS2, PageModel.LAYOUT_RECORDS, PageModel.LAYOUT_TURNS,
        PageModel.LAYOUT_CLOCK, PageModel.LAYOUT_TIMELINE];
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

    // labels off: every cell falls back to its glyph alone
    var labels = AppSettings.showLabels;
    AppSettings.showLabels = false;
    for (var i = 0; i < PageModel.count(); i++) {
        PageNav.index = i;
        view.onUpdate(dc);
    }
    AppSettings.showLabels = labels;

    // a HERO page carrying foil % draws BOTH rings — the state ring steps inside the arc
    PageModel.build({"pg1Layout" => PageModel.LAYOUT_HERO, "pg1s1" => PageModel.M_FOIL_PCT,
        "pg1s2" => PageModel.M_SPEED, "pg1s3" => PageModel.M_HR,
        "pg2Layout" => 0, "pg3Layout" => 0, "pg4Layout" => 0, "pg5Layout" => 0,
        "pg6Layout" => 0});
    PageNav.index = 0;
    Test.assertMessage(PageModel.pageHasMetric(0, PageModel.M_FOIL_PCT), "hero foil arc");
    view.onUpdate(dc);

    // the celebration paints over the page, and PAUSED must survive it
    PbFlash.fire(13.7);
    view.onUpdate(dc);
    c.state = SessionController.STATE_PAUSED;
    view.onUpdate(dc);
    c.state = was;
    PbFlash.stop();
    PageModel.build({});

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

// ---- Invite-beta unlock gate (docs/decisions.md ADR-012) ----
// The gate is worthless if the watch and lab/tools/make_unlock.py ever disagree about the
// arithmetic — Jan would mail a key that does not open the app, on a build he cannot debug
// remotely. These vectors are the contract: the SAME table is hard-coded in the keygen's
// `--check`, so a change to either implementation reddens one of the two suites.

const UNLOCK_VEC_PEPPER = [0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef];
const UNLOCK_VEC_IDS = ["wingfoil", "ac915d426451c88e8ea691fa412f9af9c21b4d12", ""];
const UNLOCK_VEC_CODES = ["PTMDBDNY", "N3J986JP", "SFS9SS44"];
const UNLOCK_VEC_KEYS = ["MWTSPKVB", "MJFJ4PD4", "1PT5WKZK"];

(:test)
function unlockKeyMatchesKeygenVectors(logger as Test.Logger) as Boolean {
    for (var i = 0; i < UNLOCK_VEC_IDS.size(); i++) {
        var code = LockGate.requestCodeFor(UNLOCK_VEC_IDS[i]);
        var key = LockGate.keyFor(UNLOCK_VEC_PEPPER, code);
        logger.debug("id=\"" + UNLOCK_VEC_IDS[i] + "\" code=" + code + " key=" + key);
        Test.assertMessage(code.equals(UNLOCK_VEC_CODES[i]),
            "request code " + code + " != keygen " + UNLOCK_VEC_CODES[i]);
        Test.assertMessage(key.equals(UNLOCK_VEC_KEYS[i]),
            "unlock key " + key + " != keygen " + UNLOCK_VEC_KEYS[i]);
    }
    // The 64-bit FNV state is carried in two 32-bit halves precisely so no multiply can
    // overflow; if a device ever wrapped or saturated differently, these two would drift.
    var h = LockGate.fnv1a64([] as Array<Number>);
    Test.assertMessage(h[0] == 0xcbf29ce4l && h[1] == 0x84222325l, "FNV offset basis");
    h = LockGate.fnv1a64([0] as Array<Number>);
    Test.assertMessage(h[0] == 0xaf63bd4cl && h[1] == 0x8601b7dfl,
        "FNV of one zero byte drifted: " + h[0].format("%08x") + h[1].format("%08x"));
    return true;
}

(:test)
function unlockGateIsOffWithoutAPepper(logger as Test.Logger) as Boolean {
    // This binary is built from monkey.jungle, i.e. the source-nopepper stub. The public
    // app must never reach the lock screen, and this is the assertion that says so.
    var p = UnlockPepper.bytes();
    Test.assertMessage(p.size() == 8, "pepper is 8 bytes");
    Test.assertMessage(LockGate.isZero(p), "public build must ship a ZERO pepper");
    Test.assertMessage(!LockGate.enabled(), "gate must be disabled in the public build");
    Test.assertMessage(LockGate.refresh(), "a disabled gate reports unlocked");
    logger.debug("zero pepper -> gate bypassed");
    return true;
}

(:test)
function unlockAcceptsOnlyItsOwnKey(logger as Test.Logger) as Boolean {
    var code = UNLOCK_VEC_CODES[0];
    var key = UNLOCK_VEC_KEYS[0];
    Test.assertMessage(LockGate.matches(UNLOCK_VEC_PEPPER, code, key), "correct key unlocks");

    // Wrong in every way that matters.
    Test.assertMessage(!LockGate.matches(UNLOCK_VEC_PEPPER, code, "ZZZZZZZZ"), "junk stays locked");
    Test.assertMessage(!LockGate.matches(UNLOCK_VEC_PEPPER, code, ""), "empty stays locked");
    Test.assertMessage(!LockGate.matches(UNLOCK_VEC_PEPPER, code, UNLOCK_VEC_KEYS[1]),
        "another tester's key stays locked");
    Test.assertMessage(!LockGate.matches(UNLOCK_VEC_PEPPER, UNLOCK_VEC_CODES[1], key),
        "a key is bound to ONE request code");
    // The gate itself: the zero pepper the public build carries must not mint this key.
    Test.assertMessage(!LockGate.matches(UnlockPepper.bytes(), code, key),
        "a different pepper must produce a different key");

    // ...and forgiving about how it was typed, because the tester is copying an 8-character
    // code out of a mail into a phone keyboard.
    Test.assertMessage(LockGate.matches(UNLOCK_VEC_PEPPER, code, key.toLower()), "lower case");
    Test.assertMessage(LockGate.matches(UNLOCK_VEC_PEPPER, code, " " + key + " "), "spaces");
    Test.assertMessage(LockGate.matches(UNLOCK_VEC_PEPPER, code,
        key.substring(0, 4) + "-" + key.substring(4, 8)), "dash");
    // Crockford folding: the alphabet has no I/L/O, so those can only be mistyped 1/1/0.
    Test.assertEqual(LockGate.normalize("i0lo"), "1010");
    Test.assertEqual(LockGate.normalize(" ptm-dbdny "), "PTMDBDNY");
    // And the request code the lock screen shows can never contain the ambiguous letters.
    Test.assertMessage(LockGate.ALPHABET.find("I") == null
        && LockGate.ALPHABET.find("L") == null
        && LockGate.ALPHABET.find("O") == null
        && LockGate.ALPHABET.find("U") == null, "alphabet must drop I/L/O/U");
    logger.debug("code " + code + " opens only for " + key);
    return true;
}

(:test)
function unlockRequestCodeIsStable(logger as Test.Logger) as Boolean {
    // Same device, same code, forever — the whole scheme rests on this. A tester who
    // reinstalls must not need a new key.
    var id = "ac915d426451c88e8ea691fa412f9af9c21b4d12";
    var a = LockGate.requestCodeFor(id);
    var b = LockGate.requestCodeFor(id);
    Test.assertEqual(a, b);
    Test.assertMessage(a.length() == LockGate.CODE_LEN, "8 characters");
    for (var i = 0; i < a.length(); i++) {
        Test.assertMessage(LockGate.ALPHABET.find(a.substring(i, i + 1)) != null,
            "code character outside the alphabet: " + a);
    }
    // Different devices, different codes (a one-character change is enough).
    Test.assertMessage(!a.equals(LockGate.requestCodeFor(id + "0")), "id change moves the code");
    Test.assertMessage(!a.equals(LockGate.requestCodeFor("b" + id.substring(1, id.length()))),
        "first-character change moves the code");
    // The live device path must produce a code of the same shape (its id is whatever the
    // simulator reports, so only the shape is assertable).
    var live = LockGate.requestCode();
    Test.assertEqual(live.length(), LockGate.CODE_LEN);
    Test.assertEqual(live, LockGate.requestCode());
    logger.debug("this device: " + live);
    return true;
}

// The lock screen is the ONE screen a tester sees before anything works, and its one job is
// to render 8 characters legibly on round glass. Same measurement as the recording pages.
(:test)
function lockScreenFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var h = screenPx();
    var cy = h / 2;
    var radius = h / 2.0 - BEZEL;
    var code = "WWWWWWWW";     // widest 8 characters the alphabet can produce

    var fonts = [Graphics.FONT_SMALL, Graphics.FONT_XTINY, LockView.codeFont(dc, code),
        Graphics.FONT_XTINY, Graphics.FONT_XTINY, Graphics.FONT_XTINY];
    var texts = ["WingFoil", "INVITE BETA", code, "key not valid", "key goes in Garmin",
        "Connect app settings"];

    var prevY = -1;
    var prevH = 0;
    for (var i = 0; i < texts.size(); i++) {
        var fh = dc.getFontHeight(fonts[i]);
        var y = LockView.rowY(h, i);
        var w = dc.getTextWidthInPixels(texts[i], fonts[i]);
        var r = cornerRadius(w, fh, y, cy);
        logger.debug("row " + i.toString() + " y=" + y.toString() + " " + w.toString() + "x"
            + fh.toString() + " corner " + r.format("%.0f"));
        Test.assertMessage(r <= radius,
            "lock row " + i.toString() + " corner " + r.format("%.0f") + " > " + radius);
        if (prevY >= 0) {
            Test.assertMessage(y - prevY >= (prevH + fh) / 2,
                "lock rows " + (i - 1).toString() + "/" + i.toString() + " collide");
        }
        prevY = y;
        prevH = fh;
    }

    // "As big as this row can hold" is the requirement, not an accident of the fitter. The
    // bitmap ladder's best fit is the floor the vector path must beat — on the fenix 7 family
    // the widest vector size that fits an 8-character code is SHORTER than that variant's
    // FONT_LARGE, so a fitter that preferred vectors unconditionally would have shrunk the one
    // string a tester has to transcribe. (Not "at least FONT_LARGE": on the 416 px fenix 8
    // 43 mm, FONT_LARGE itself overflows this row by a hair and FONT_MEDIUM is the ladder's
    // honest answer.)
    var lad = LockView.ladder();
    var codeDy = (LockView.rowY(h, LockView.ROW_CODE) - h / 2).abs();
    var bitmapBest = RecordingView.fitFont(dc, lad, 0, code,
        RecordingView.rowBudget(RecordingView.fitRadius(dc, false, false), codeDy,
            dc.getFontHeight(lad[0])) * LockView.CODE_FIT_PCT / 100);
    var codeH = dc.getFontHeight(fonts[2]);
    Test.assertMessage(codeH >= dc.getFontHeight(bitmapBest),
        "request code font is only " + codeH.toString() + "px, the bitmap ladder offers "
            + dc.getFontHeight(bitmapBest).toString());
    // ...and it must never collapse to body text.
    Test.assertMessage(codeH > dc.getFontHeight(Graphics.FONT_SMALL),
        "request code font " + codeH.toString() + "px is no bigger than FONT_SMALL");
    // ...and the real code must be no wider than the worst case just measured.
    Test.assertMessage(
        dc.getTextWidthInPixels(LockGate.requestCode(), fonts[2])
            <= dc.getTextWidthInPixels(code, fonts[2]), "WWWWWWWW is the widest case");

    // It renders, in both states, without throwing.
    var view = new LockView();
    view.onUpdate(dc);
    logger.debug("lock screen code font height " + codeH.toString() + "px");
    return true;
}

// ---- Phase-5 companion link (source/comm/PhoneLink.mc) ----
// The BLE hop itself cannot be exercised here: transmit needs a paired phone running the
// companion app, which no simulator provides. Everything ABOVE the radio can be, and is —
// PhoneLink.radio is a one-method seam these tests replace with a stand-in that succeeds or
// fails on command, so the branches that decide whether a rider's card survives an offline
// save are covered without a single real byte going out.

// Stands in for the radio. Records what it was handed and drives the listener the way a real
// send would: onComplete when the phone acknowledged, onError when it never arrived.
class FakeRadio extends PhoneLink.Radio {
    var succeed as Boolean = true;
    var sent as Number = 0;
    var lastPayload as Dictionary?;

    function initialize(ok as Boolean) {
        PhoneLink.Radio.initialize();
        succeed = ok;
    }

    function send(payload as Dictionary, listener as Communications.ConnectionListener) as Void {
        sent++;
        lastPayload = payload;
        if (succeed) {
            listener.onComplete();
        } else {
            listener.onError();
        }
    }
}

// A controller carrying a realistic full session: two hours on Lake Garda, ~70% foiling,
// 38 km, a pile of turns. This is the payload the size budget is judged on — a fresh
// controller full of zeros would prove nothing about the encoding.
function fullSessionController() as SessionController {
    var c = new SessionController();
    c.startEpochS = 1786000000;          // ten-digit UNIX epoch, the worst case for width
    c.elapsedS = 7412;
    var e = c.engine;
    e.detector.foilTimeS = 5183.4;
    e.detector.flightCount = 47;
    e.detector.longestS = 412.7;
    e.detector.longestM = 4830.2;
    e.distM = 38412.5;
    e.records.best2sMps = 12.75;
    e.records.best10sMps = 11.5;
    e.turns.turnCount = 96;
    e.turns.tackCount = 41;
    e.turns.jibeCount = 52;
    e.turns.flewCount = 63;
    e.turns.touchdownCount = 21;
    e.turns.fellCount = 12;
    e.pump.successes = 39;
    e.pump.failed = 17;
    return c;
}

// Every key present, every value a Number, version tag first. The phone decodes this blind:
// a missing key is a blank on the card, a Float is a parse the other side may not survive,
// and a payload whose schema cannot be read before the rest is a payload that must be
// guessed at.
(:test)
function phoneLinkPayloadShape(logger as Test.Logger) as Boolean {
    var c = fullSessionController();
    var p = PhoneLink.summary(c);

    var expected = [PhoneLink.KEY_VERSION, PhoneLink.KEY_START, PhoneLink.KEY_DUR,
        PhoneLink.KEY_FOIL_TIME, PhoneLink.KEY_FOIL_PCT, PhoneLink.KEY_FLIGHTS,
        PhoneLink.KEY_LONGEST_S, PhoneLink.KEY_LONGEST_M, PhoneLink.KEY_DIST_M,
        PhoneLink.KEY_BEST_2S, PhoneLink.KEY_BEST_10S, PhoneLink.KEY_TURNS,
        PhoneLink.KEY_TACKS, PhoneLink.KEY_JIBES, PhoneLink.KEY_FLEW,
        PhoneLink.KEY_TOUCHDOWN, PhoneLink.KEY_FELL, PhoneLink.KEY_TAKEOFF_ATT,
        PhoneLink.KEY_TAKEOFF_OK, PhoneLink.KEY_WIND, PhoneLink.KEY_APP];
    for (var i = 0; i < expected.size(); i++) {
        Test.assertMessage(p.hasKey(expected[i]), "payload is missing key " + expected[i]);
    }
    Test.assertMessage(p.size() == expected.size(),
        "payload carries " + p.size().toString() + " keys, the card wants "
        + expected.size().toString() + " — a new key needs a test and a phone that reads it");

    var keys = p.keys();
    for (var i = 0; i < keys.size(); i++) {
        var v = p[keys[i]];
        Test.assertMessage(v instanceof Lang.Number,
            "key " + keys[i] + " is not a Number — no floats, no strings on this channel");
    }
    // The schema tag, so a reader can refuse a payload it does not understand before it has
    // interpreted a single number.
    //
    // It is NOT asserted to be the first key, because on this platform no sender can put it
    // there: Monkey C Dictionary.keys() returns hash order, not insertion order (this test
    // originally asserted keys[0] and got "ds"), and the payload arrives on iOS as an
    // unordered dictionary anyway. Key order is not a wire property either side can observe,
    // so what is enforced instead is what the phone actually does — look the version up by
    // key, before anything else, and find exactly one candidate.
    Test.assertMessage(p.hasKey(PhoneLink.KEY_VERSION), "no schema version in the payload");
    Test.assertEqual(p[PhoneLink.KEY_VERSION], PhoneLink.SCHEMA);
    for (var i = 0; i < keys.size(); i++) {
        var k = keys[i] as String;
        Test.assertMessage(k.length() >= 1 && k.length() <= 2,
            "key " + k + " is longer than the two characters this channel budgets for");
        Test.assertMessage(k.equals(PhoneLink.KEY_VERSION) || k.length() == 2,
            "key " + k + " is one character, which is the schema tag's reserved shape");
    }

    // The dedupe key means what the FIT means: start_time and total_elapsed_time, unmangled.
    Test.assertEqual(p[PhoneLink.KEY_START], 1786000000);
    Test.assertEqual(p[PhoneLink.KEY_DUR], 7412);

    // Units, on the numbers where getting them wrong is invisible on the watch and obvious
    // on the phone: cm/s for speeds, whole seconds and metres, percent as 0-100.
    Test.assertEqual(p[PhoneLink.KEY_BEST_2S], 1275);
    Test.assertEqual(p[PhoneLink.KEY_BEST_10S], 1150);
    Test.assertEqual(p[PhoneLink.KEY_FOIL_TIME], 5183);
    Test.assertEqual(p[PhoneLink.KEY_LONGEST_S], 412);
    Test.assertEqual(p[PhoneLink.KEY_LONGEST_M], 4830);
    Test.assertEqual(p[PhoneLink.KEY_DIST_M], 38412);
    Test.assertEqual(p[PhoneLink.KEY_FOIL_PCT], 69);        // 5183.4 / 7412
    Test.assertEqual(p[PhoneLink.KEY_TAKEOFF_ATT], 56);     // successes + failed
    Test.assertEqual(p[PhoneLink.KEY_TAKEOFF_OK], 39);
    Test.assertEqual(p[PhoneLink.KEY_FLEW], 63);
    Test.assertEqual(p[PhoneLink.KEY_TOUCHDOWN], 21);
    Test.assertEqual(p[PhoneLink.KEY_FELL], 12);
    Test.assertEqual(p[PhoneLink.KEY_APP],
        FitSchema.APP_MINOR * 256 + FitSchema.SCHEMA_VERSION);

    // A percentage cannot exceed 100 however the two clocks disagree, and a zero-length
    // session must not divide by it.
    c.elapsedS = 0;
    Test.assertEqual(PhoneLink.summary(c)[PhoneLink.KEY_FOIL_PCT], 0);
    c.elapsedS = 10;
    Test.assertEqual(PhoneLink.summary(c)[PhoneLink.KEY_FOIL_PCT], 100);
    logger.debug("payload: " + p.size().toString()
        + " keys, all Numbers, schema tag findable by key");
    return true;
}

// The size budget, measured on the payload above rather than on a guess. transmit is a
// notification channel; the plan's 10 KB is what the radio tolerates, not what a summary
// should cost. Anything that pushes this over 1 KB is a new transport, not a bigger message.
(:test)
function phoneLinkPayloadFitsBudget(logger as Test.Logger) as Boolean {
    var p = PhoneLink.summary(fullSessionController());
    var bytes = PhoneLink.estimateBytes(p);
    logger.debug("realistic full session: " + p.size().toString() + " keys, "
        + bytes.toString() + " B encoded (budget " + PhoneLink.BUDGET_BYTES.toString() + ")");
    Test.assertMessage(bytes <= PhoneLink.BUDGET_BYTES,
        "payload is " + bytes.toString() + " B, budget is "
        + PhoneLink.BUDGET_BYTES.toString());
    // Headroom, so the key that breaks the budget trips this with room to fix it.
    Test.assertMessage(bytes <= PhoneLink.BUDGET_BYTES / 2,
        "payload is " + bytes.toString() + " B, over half the budget already");
    return true;
}

// One slot, newest wins. Three sessions with the phone in the car must leave the NEWEST card
// waiting, not a queue that replays the stale ones first.
(:test)
function phoneLinkPendingIsNewestWins(logger as Test.Logger) as Boolean {
    var saved = PhoneLink.radio;
    var fake = new FakeRadio(false);            // nothing gets through
    PhoneLink.radio = fake;
    PhoneLink.clearPending();
    AppSettings.phonePush = true;

    var c = fullSessionController();
    Test.assertMessage(PhoneLink.pending() == null, "starts empty");

    c.startEpochS = 1000;
    PhoneLink.sendSummary(c);
    c.startEpochS = 2000;
    PhoneLink.sendSummary(c);
    c.startEpochS = 3000;
    PhoneLink.sendSummary(c);

    var p = PhoneLink.pending();
    Test.assertMessage(p != null, "three offline saves left nothing to send");
    Test.assertEqual((p as Dictionary)[PhoneLink.KEY_START], 3000);
    logger.debug("3 offline saves -> 1 pending card, start=3000");

    // The setting is a real off switch: no stash, no radio.
    PhoneLink.clearPending();
    AppSettings.phonePush = false;
    var before = fake.sent;
    Test.assertMessage(!PhoneLink.sendSummary(c), "push disabled must report not-sent");
    Test.assertMessage(PhoneLink.pending() == null, "push disabled must not stash");
    Test.assertEqual(fake.sent, before);

    AppSettings.phonePush = true;
    PhoneLink.clearPending();
    PhoneLink.radio = saved;
    return true;
}

// The branch the rider's card lives or dies on. A failed send is the ROUTINE case — phone in
// the car, app not running — so it must leave the slot exactly as it was; a successful one
// must clear it, or the next app start re-sends a card the phone already has.
(:test)
function phoneLinkFailedSendKeepsTheSlot(logger as Test.Logger) as Boolean {
    var saved = PhoneLink.radio;
    AppSettings.phonePush = true;
    var c = fullSessionController();
    c.startEpochS = 4242;

    // fail
    var bad = new FakeRadio(false);
    PhoneLink.radio = bad;
    PhoneLink.clearPending();
    PhoneLink.sendSummary(c);
    Test.assertEqual(bad.sent, 1);
    var p = PhoneLink.pending();
    Test.assertMessage(p != null, "a failed send threw the card away");
    Test.assertEqual((p as Dictionary)[PhoneLink.KEY_START], 4242);
    Test.assertMessage(!PhoneLink.lastSendOk, "a failed send did not record the failure");

    // retry on the connected edge / at app start, still failing: still there
    PhoneLink.send();
    Test.assertEqual(bad.sent, 2);
    Test.assertMessage(PhoneLink.pending() != null, "a failed retry threw the card away");

    // ...and now the phone answers
    var good = new FakeRadio(true);
    PhoneLink.radio = good;
    Test.assertMessage(PhoneLink.send(), "send() reported no attempt with a slot pending");
    Test.assertEqual(good.sent, 1);
    Test.assertEqual((good.lastPayload as Dictionary)[PhoneLink.KEY_START], 4242);
    Test.assertMessage(PhoneLink.pending() == null, "a delivered card stayed pending");
    Test.assertMessage(PhoneLink.lastSendOk, "a delivered card did not record success");

    // an empty slot never touches the radio
    Test.assertMessage(!PhoneLink.send(), "send() with nothing pending claimed an attempt");
    Test.assertEqual(good.sent, 1);

    logger.debug("fail -> slot kept (2 attempts), success -> slot cleared");
    PhoneLink.radio = saved;
    return true;
}

// The inbound wind push. This is untrusted input from another process on another device, and
// a bad wind axis does not fail loudly — it silently relabels every tack as a jibe for the
// rest of the session. So: integer degrees 0..359, or -1 to clear, and nothing else.
(:test)
function phoneLinkWindPushValidatesHard(logger as Test.Logger) as Boolean {
    var before = AppSettings.cfg.windDirection;

    AppSettings.storeWindDirection(90);
    Test.assertMessage(PhoneLink.applyWind(0), "0 deg (north) is a legal bearing");
    Test.assertEqual(AppSettings.cfg.windDirection, 0);

    Test.assertMessage(PhoneLink.applyWind(359), "359 deg is a legal bearing");
    Test.assertEqual(AppSettings.cfg.windDirection, 359);

    Test.assertMessage(PhoneLink.applyWind(-1), "-1 clears the wind axis");
    Test.assertEqual(AppSettings.cfg.windDirection, -1);

    // Rejections leave the axis untouched — a bad push must not clear a good value either.
    AppSettings.storeWindDirection(225);
    var bad = [360, -2, 1000, -100000, "SW", "225", 225.0, true, null];
    for (var i = 0; i < bad.size(); i++) {
        Test.assertMessage(!PhoneLink.applyWind(bad[i]),
            "accepted a wind push it had no business trusting: index " + i.toString());
        Test.assertMessage(AppSettings.cfg.windDirection == 225,
            "a rejected wind push moved the axis: index " + i.toString());
    }

    // The whole inbound path, dictionary and all: junk in, nothing moved.
    Test.assertMessage(!PhoneLink.applyMessage(null), "a null message body was believed");
    Test.assertMessage(!PhoneLink.applyMessage("wind please"), "a String body was believed");
    Test.assertMessage(!PhoneLink.applyMessage({"zz" => 12}), "a foreign key was believed");
    Test.assertMessage(!PhoneLink.applyMessage({PhoneLink.KEY_IN_WIND => 400}),
        "400 deg was believed");
    Test.assertEqual(AppSettings.cfg.windDirection, 225);
    // ...and a well-formed push lands through the same path the wind menu uses.
    Test.assertMessage(PhoneLink.applyMessage({PhoneLink.KEY_IN_WIND => 315}),
        "a well-formed wind push was refused");
    Test.assertEqual(AppSettings.cfg.windDirection, 315);
    Test.assertEqual(AppSettings.windLabel(), "NW");

    AppSettings.storeWindDirection(before);
    logger.debug("wind push: 0/359/-1 accepted, 360/-2/float/string/bool/null rejected");
    return true;
}


// ---- RECORDS page ----
// The page that had no geometry test, and was therefore the only page still drawing a giant
// without a fitter and with a magic `cy + 12` bias. Measured with the real metrics, that bias
// put 229 px of NUMBER_HOT ink into the 206 px chord at the bottom row's depth on a 454 px
// glass — the leading digit and the decimal point sliced off — and 30 px over on the 43 mm.
// This is the assertion that would have caught it.
(:test)
function recordsPageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = screenPx() / 2;
    var radius = RecordingView.fitRadius(dc, false, false);
    var limit = radius.toFloat();
    var hHot = dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var ink = RecordingView.inkH(dc, Graphics.FONT_NUMBER_HOT);

    // the block is centred on the glass — no bias of any kind survives
    var yTop = RecordingView.recordsRowY(cy, hHot, hT, 0) - hT / 2;
    var yBot = RecordingView.recordsRowY(cy, hHot, hT, 3) + hHot / 2;
    // Two pixels, not one: the stack is built from three integer halvings (the block height,
    // then hT/2, then hHot/2), and on a glass whose font heights are odd each one can drop a
    // pixel. What is being asserted is "centred", not "centred to the pixel" — the bias this
    // replaced was 12 px, in one direction, on purpose.
    Test.assertMessage(((cy - yTop) - (yBot - cy)).abs() <= 2,
        "records block off centre: " + (cy - yTop).toString() + " vs "
            + (yBot - cy).toString());

    // rows in order, no overlap
    for (var row = 1; row <= 3; row++) {
        var prev = RecordingView.recordsRowY(cy, hHot, hT, row - 1);
        var here = RecordingView.recordsRowY(cy, hHot, hT, row);
        var gap = row % 2 == 1 ? (hT + hHot) / 2 : (hHot + hT) / 2;
        Test.assertMessage(here - prev >= gap,
            "records rows " + (row - 1).toString() + "/" + row.toString() + " collide");
    }

    // Both labels, each at ITS real content. They differ on purpose: only the lower one
    // carries the unit, because the upper row sits nearer the top of the circle where the
    // chord is narrowest — which is the thing the deleted `cy + 12` bias was trying to fix
    // with a magic number instead of with the string.
    var labels = ["best 2s", "best 10s km/h"];
    for (var row = 0; row <= 2; row += 2) {
        var y = RecordingView.recordsRowY(cy, hHot, hT, row);
        var lbl = labels[row / 2];
        var r = cornerRadius(dc.getTextWidthInPixels(lbl, Graphics.FONT_XTINY),
            RecordingView.inkH(dc, Graphics.FONT_XTINY), y, cy);
        Test.assertMessage(r <= limit, "records label '" + lbl + "' row " + row.toString()
            + " r=" + r.format("%.0f") + " > " + limit);
    }

    // ...and both NUMBERS, through the same fitter the renderer uses. "99.9" is the fastest
    // reading either unit can produce; the deeper of the two rows is the one that used to clip.
    var shrunk = 0;
    for (var row = 1; row <= 3; row += 2) {
        var y = RecordingView.recordsRowY(cy, hHot, hT, row);
        var f = RecordingView.fitFont(dc, NUMBER_FONTS, 1, "99.9",
            RecordingView.rowBudget(radius, y - cy, ink));
        var r = cornerRadius(dc.getTextWidthInPixels("99.9", f),
            RecordingView.inkH(dc, f), y, cy);
        Test.assertMessage(r <= limit, "records value row " + row.toString() + " r="
            + r.format("%.0f") + " > " + limit);
        if (f != Graphics.FONT_NUMBER_HOT) { shrunk++; }
    }
    logger.debug("records rows " + RecordingView.recordsRowY(cy, hHot, hT, 0).toString() + "/"
        + RecordingView.recordsRowY(cy, hHot, hT, 1).toString() + "/"
        + RecordingView.recordsRowY(cy, hHot, hT, 2).toString() + "/"
        + RecordingView.recordsRowY(cy, hHot, hT, 3).toString()
        + ", " + shrunk.toString() + " of 2 numbers stepped below NUMBER_HOT");
    return true;
}

// ---- MAIN page (the default page 1) ----
// Five rows, all fitted, on a page that also paints the flight-state ring — so every row is
// measured against the RING-aware radius, not the glass.
(:test)
function mainPageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = screenPx() / 2;
    var radius = RecordingView.fitRadius(dc, true, false);
    var limit = radius.toFloat();
    var hS = dc.getFontHeight(Graphics.FONT_SMALL);
    var hN = dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hL = dc.getFontHeight(Graphics.FONT_LARGE);
    var hM = dc.getFontHeight(Graphics.FONT_MEDIUM);

    // the ring-aware radius must actually be TIGHTER than the glass, or the fix is inert
    Test.assertMessage(radius < RecordingView.fitRadius(dc, false, false),
        "fitRadius ignores the state ring");

    // rows in order, no overlap, block centred
    var y0 = RecordingView.mainRowY(cy, hS, hN, hT, hL, hM, 0);
    var y1 = RecordingView.mainRowY(cy, hS, hN, hT, hL, hM, 1);
    var y2 = RecordingView.mainRowY(cy, hS, hN, hT, hL, hM, 2);
    var y3 = RecordingView.mainRowY(cy, hS, hN, hT, hL, hM, 3);
    var y4 = RecordingView.mainRowY(cy, hS, hN, hT, hL, hM, 4);
    Test.assertMessage(y1 - y0 >= (hS + hN) / 2, "main clock/giant overlap");
    Test.assertMessage(y2 - y1 >= (hN + hT) / 2, "main giant/unit overlap");
    Test.assertMessage(y3 - y2 >= (hT + hL) / 2, "main unit/outcomes overlap");
    Test.assertMessage(y4 - y3 >= (hL + hM) / 2, "main outcomes/streak overlap");
    Test.assertMessage((((cy - (y0 - hS / 2)) - ((y4 + hM / 2) - cy)).abs() <= 1),
        "main block off centre: " + (cy - (y0 - hS / 2)).toString() + " vs "
            + ((y4 + hM / 2) - cy).toString());

    // row 0 — the clock, and the PAUSED word that replaces it. Both must fit the same row.
    var tops = ["23:59", PAUSED_TEXT];
    for (var i = 0; i < tops.size(); i++) {
        var f = RecordingView.fitFont(dc, TEXT_FONTS, 2, tops[i],
            RecordingView.rowBudget(radius, y0 - cy, RecordingView.inkH(dc, Graphics.FONT_SMALL)));
        var r = cornerRadius(dc.getTextWidthInPixels(tops[i], f),
            RecordingView.inkH(dc, f), y0, cy);
        Test.assertMessage(r <= limit,
            "main row0 '" + tops[i] + "' r=" + r.format("%.0f") + " > " + limit);
        Test.assertEqual(f, Graphics.FONT_SMALL);
    }

    // row 1 — the hero. It must NOT have to step down: putting the clock above the giant is
    // what keeps the giant near the equator, and if the fitter shrinks it the trade failed.
    var gf = RecordingView.fitFont(dc, NUMBER_FONTS, 1, "99.9",
        RecordingView.rowBudget(radius, y1 - cy,
            RecordingView.inkH(dc, Graphics.FONT_NUMBER_HOT)));
    var r = cornerRadius(dc.getTextWidthInPixels("99.9", gf),
        RecordingView.inkH(dc, gf), y1, cy);
    Test.assertMessage(r <= limit, "main giant r=" + r.format("%.0f") + " > " + limit);
    Test.assertEqual(gf, Graphics.FONT_NUMBER_HOT);

    // row 2 — the unit line
    r = cornerRadius(dc.getTextWidthInPixels("km/h", Graphics.FONT_XTINY),
        RecordingView.inkH(dc, Graphics.FONT_XTINY), y2, cy);
    Test.assertMessage(r <= limit, "main unit r=" + r.format("%.0f") + " > " + limit);

    // row 3 — the outcome ladder at its worst case: three two-digit counts, no verdict.
    var tBudget = RecordingView.rowBudget(radius, y3 - cy,
        RecordingView.inkH(dc, Graphics.FONT_LARGE));
    var tf = RecordingView.tallyFont(dc, "99", "99", "99", "", tBudget, 0);
    var mask = RecordingView.tallyContent(dc, "99", "99", "99", "", tBudget, tf);
    Test.assertMessage(mask >= 0, "main outcome row cannot hold three counts");
    var sep = (mask & TALLY_SEPARATORS) != 0 ? TURNS_TALLY_SEP : TALLY_SEP_NARROW;
    r = cornerRadius(RecordingView.tallyWidth(dc, "99", "99", "99", "", sep, tf),
        RecordingView.inkH(dc, tf), y3, cy);
    Test.assertMessage(r <= limit, "main outcomes r=" + r.format("%.0f") + " > " + limit);
    // the counts are rider-relevant numbers and must stay big — never a label font
    Test.assertMessage(dc.getFontHeight(tf) >= dc.getFontHeight(Graphics.FONT_SMALL),
        "main outcome counts fell below FONT_SMALL");

    // row 4 — the streak, at "dry 99 / 99"
    var sBudget = RecordingView.rowBudget(radius, y4 - cy,
        RecordingView.inkH(dc, Graphics.FONT_MEDIUM));
    var sf = RecordingView.streakFont(dc, "99", "99", sBudget);
    r = cornerRadius(RecordingView.streakWidth(dc, "99", "99", sf),
        RecordingView.inkH(dc, sf), y4, cy);
    Test.assertMessage(r <= limit, "main streak r=" + r.format("%.0f") + " > " + limit);
    Test.assertMessage(dc.getFontHeight(sf) >= dc.getFontHeight(Graphics.FONT_SMALL),
        "main streak fell below FONT_SMALL");
    // a one-digit streak must never be WIDER than the two-digit worst case
    Test.assertMessage(RecordingView.streakWidth(dc, "7", "12", sf)
        <= RecordingView.streakWidth(dc, "99", "99", sf), "streak worst case is not worst");
    logger.debug("main rows " + y0.toString() + "/" + y1.toString() + "/" + y2.toString()
        + "/" + y3.toString() + "/" + y4.toString() + " on r=" + radius.toString()
        + " (glass " + RecordingView.fitRadius(dc, false, false).toString() + ")");
    return true;
}

// ---- PAUSED banner ----
// It used to be `y = 18` with an opaque background: a black box from y 18 to 71 painted
// straight across the flight ring, the nested ring and the foil-% arc, so pausing bit a hole
// out of whichever ring the page was showing. The banner is now placed at the deepest y whose
// own corners still clear the radius the page's text is fitted to — i.e. inside every ring.
(:test)
function pausedBannerStaysInsideTheRings(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = screenPx() / 2;
    var font = TEXT_FONTS[PAUSED_FONT_IDX];
    var w = dc.getTextWidthInPixels(PAUSED_TEXT, font);
    var h = dc.getFontHeight(font);

    // every ring combination a page can draw
    var rings = [RecordingView.fitRadius(dc, false, false),
        RecordingView.fitRadius(dc, true, false),
        RecordingView.fitRadius(dc, false, true),
        RecordingView.fitRadius(dc, true, true)];
    for (var i = 0; i < rings.size(); i++) {
        var radius = rings[i];
        var y = RecordingView.pausedBannerY(dc, w, radius);
        // the OPAQUE box, full line height — that is what erases whatever is under it
        var r = cornerRadius(w, h, y, cy);
        Test.assertMessage(r <= radius.toFloat() + 1.0,
            "paused banner corner " + r.format("%.0f") + " > radius " + radius.toString()
                + " (case " + i.toString() + ")");
        Test.assertMessage(y < cy, "the banner must stay in the top half");
        Test.assertMessage(y - h / 2 >= 0, "the banner runs off the top of the glass");
    }
    // a tighter radius must push it DOWN, further inside the glass, never up
    Test.assertMessage(
        RecordingView.pausedBannerY(dc, w, RecordingView.fitRadius(dc, true, true))
            >= RecordingView.pausedBannerY(dc, w, RecordingView.fitRadius(dc, false, false)),
        "a nested-ring page must tuck the banner further in");
    logger.debug("paused banner " + w.toString() + "x" + h.toString() + " at y "
        + RecordingView.pausedBannerY(dc, w, rings[1]).toString()
        + " for the ring radius " + rings[1].toString());
    return true;
}

// ---- Post-save summary ----
// The rebuilt multi-page review. The old screen advanced 32 px at a font whose line height is
// 53, so consecutive rows overlapped by 7 px of ink — this asserts the pitch can never again
// be smaller than the line, on every page, plus the round-glass fit of every row.
(:test)
function summaryPagesFitRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = screenPx() / 2;
    var hN = dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT);
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hL = dc.getFontHeight(Graphics.FONT_LARGE);
    var hM = dc.getFontHeight(Graphics.FONT_MEDIUM);

    // THE regression this screen exists to prevent: pitch >= line height, always. The old
    // SummaryView stacked five FONT_SMALL rows 32 px apart against a 53 px line.
    for (var nSub = 0; nSub <= 2; nSub++) {
        var a = RecordingView.heroRowY(cy, hN, hT, hL, hM, 1, nSub);
        if (nSub >= 1) {
            var b = RecordingView.heroRowY(cy, hN, hT, hL, hM, 2, nSub);
            Test.assertMessage(b - a >= (hT + hL) / 2,
                "summary pitch " + (b - a).toString() + " < half the two line heights");
            Test.assertMessage(b - a >= dc.getFontHeight(Graphics.FONT_SMALL) / 2,
                "summary pitch below a FONT_SMALL half-line");
            if (nSub == 2) {
                var d = RecordingView.heroRowY(cy, hN, hT, hL, hM, 3, nSub);
                Test.assertMessage(d - b >= (hL + hM) / 2, "summary sub-rows collide");
            }
        }
    }

    // Every page's worst-case content, through the same fitters SummaryView draws with. The
    // arc flag matters: the Verdict page paints the foil arc, so it gets a tighter radius.
    var giants = ["100%", "99.9", "199:59", "100%", "99/99"];
    var arcs = [true, false, false, false, false];
    var units = ["on foil", "best 2s km/h", "longest flight", "turns", "takeoffs"];
    var rows1 = ["199:59 foil", "10s 99.9", "999 flights", "99/99 · run 99",
        "99.9 to foil"];
    var rows2 = ["of 199:59", "99.9 km", "99.9 km", "", "+199 bpm"];
    for (var i = 0; i < giants.size(); i++) {
        var radius = RecordingView.fitRadius(dc, false, arcs[i]);
        var limit = radius.toFloat();
        var nSub = (rows1[i].equals("") ? 0 : 1) + (rows2[i].equals("") ? 0 : 1);

        var y = RecordingView.heroRowY(cy, hN, hT, hL, hM, 0, nSub);
        var f = RecordingView.fitFont(dc, NUMBER_FONTS, 0, giants[i],
            RecordingView.rowBudget(radius, y - cy,
                RecordingView.inkH(dc, Graphics.FONT_NUMBER_THAI_HOT)));
        var r = cornerRadius(dc.getTextWidthInPixels(giants[i], f),
            RecordingView.inkH(dc, f), y, cy);
        Test.assertMessage(r <= limit, "summary " + i.toString() + " giant r="
            + r.format("%.0f") + " > " + limit);
        Test.assertMessage(dc.getFontHeight(f) >= dc.getFontHeight(Graphics.FONT_NUMBER_MILD),
            "summary " + i.toString() + " giant fell out of the number ladder");

        y = RecordingView.heroRowY(cy, hN, hT, hL, hM, 1, nSub);
        r = cornerRadius(dc.getTextWidthInPixels(units[i], Graphics.FONT_XTINY),
            RecordingView.inkH(dc, Graphics.FONT_XTINY), y, cy);
        Test.assertMessage(r <= limit, "summary " + i.toString() + " unit r="
            + r.format("%.0f") + " > " + limit);

        var texts = [rows1[i], rows2[i]];
        for (var k = 0; k < 2; k++) {
            if (texts[k].equals("")) { continue; }
            y = RecordingView.heroRowY(cy, hN, hT, hL, hM, 2 + k, nSub);
            var tf = RecordingView.fitFont(dc, TEXT_FONTS, k, texts[k],
                RecordingView.rowBudget(radius, y - cy,
                    RecordingView.inkH(dc, TEXT_FONTS[k])));
            r = cornerRadius(dc.getTextWidthInPixels(texts[k], tf),
                RecordingView.inkH(dc, tf), y, cy);
            Test.assertMessage(r <= limit, "summary " + i.toString() + " row"
                + k.toString() + " r=" + r.format("%.0f") + " > " + limit);
            // a value row that has fallen to a label font is the old summary all over again
            Test.assertMessage(dc.getFontHeight(tf) >= dc.getFontHeight(Graphics.FONT_SMALL),
                "summary " + i.toString() + " row" + k.toString() + " below FONT_SMALL");
        }
    }

    // the SAVED pill sits on the TOP arc (the verdict page's eyebrow); the dots hang off
    // the bottom. The pill's old bottom slot overprinted the verdict's second sub-row.
    var savedW = dc.getTextWidthInPixels(SUM_SAVED, Graphics.FONT_XTINY);
    var rSaved = cornerRadius(savedW, RecordingView.inkH(dc, Graphics.FONT_XTINY),
        SummaryView.savedY(dc), cy);
    Test.assertMessage(rSaved <= RecordingView.fitRadius(dc, false, true).toFloat(),
        "SAVED pill corner " + rSaved.format("%.0f") + " off the glass");
    Test.assertMessage(SummaryView.savedY(dc) + dc.getFontHeight(Graphics.FONT_XTINY) / 2
        < cy - dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT) / 2,
        "SAVED pill reaches the verdict giant");
    var dr = SummaryView.dotRadius(dc);
    var dotN = 7;                                   // every page the summary can produce
    var dotW = dotN * (2 * dr + SUM_DOT_GAP) - SUM_DOT_GAP;
    var rDots = cornerRadius(dotW, 2 * dr, screenPx() - SummaryView.dotBand(dc), cy);
    Test.assertMessage(rDots <= RecordingView.fitRadius(dc, false, false).toFloat(),
        "summary dot row corner " + rDots.format("%.0f") + " off the glass");

    // the track page's box, and the aspect rule: a long thin track must stay long and thin.
    // `trackBox` is the FULL side of the inscribed square — the drawn track spans `box`
    // pixels on its longer axis, so `box` itself must sit inside the glass.
    var box = SummaryView.trackBox(dc);
    Test.assertMessage(box <= screenPx(), "track box wider than the glass");
    Test.assertMessage(cornerRadius(box, box, cy, cy)
        <= RecordingView.fitRadius(dc, false, false).toFloat() + 1.0,
        "track box corners off the glass");
    var wide = SummaryView.trackScale(box, 0.030, 0.002);
    Test.assertMessage((0.030 * wide).toNumber() <= box + 1,
        "a wide track overflows its box");
    Test.assertMessage((0.002 * wide).toNumber() < box / 4,
        "a 15:1 track was stretched to fill the box");
    // a degenerate (single-point) track must produce a finite scale, not an infinity
    Test.assertMessage(SummaryView.trackScale(box, 0.0, 0.0) <= 1.0e8, "degenerate track");
    logger.debug("summary: dots r" + dr.toString() + ", track box " + box.toString()
        + "px, SAVED at y " + SummaryView.savedY(dc).toString());
    return true;
}

// The page LIST is per session, and every page must PAINT — the headless twin of paging
// through the summary after a save.
(:test)
function summaryPagesBuildAndRenderHeadless(logger as Test.Logger) as Boolean {
    var ref = Graphics.createBufferedBitmap({:width => screenPx(), :height => screenPx()});
    var bmp = ref.get();
    Test.assertMessage(bmp != null, "buffered bitmap");
    var dc = (bmp as Graphics.BufferedBitmap).getDc();
    var c = getApp().controller;
    var saved = c.engine;

    // a bare session: no turns, no pumping, no track. Those pages must not exist.
    c.engine = new MetricsEngine();
    c.engine.timerS = 600.0;
    SummaryNav.build(c);
    Test.assertEqual(SummaryNav.count(), 4);        // verdict, speed, flights, story
    var view = new SummaryView();
    for (var i = 0; i < SummaryNav.count(); i++) {
        SummaryNav.index = i;
        Test.assertMessage(SummaryNav.pageAt(i) != SummaryNav.S_TURNS, "no turns page");
        Test.assertMessage(SummaryNav.pageAt(i) != SummaryNav.S_TAKEOFFS, "no takeoff page");
        Test.assertMessage(SummaryNav.pageAt(i) != SummaryNav.S_TRACK, "no track page");
        view.onUpdate(dc);
    }

    // a full session: every page earned, every page painted, at worst-case content.
    var e = c.engine;
    e.timerS = 7412.0;
    e.distM = 38412.5;
    e.detector.foilTimeS = 5183.4;
    e.detector.flightCount = 47;
    e.detector.longestS = 412.7;
    e.detector.longestM = 4830.2;
    e.records.best2sMps = 12.75;
    e.records.best10sMps = 11.5;
    e.turns.turnCount = 96;
    e.turns.tackCount = 41;
    e.turns.jibeCount = 52;
    e.turns.flewCount = 63;
    e.turns.touchdownCount = 21;
    e.turns.fellCount = 12;
    e.turns.successCount = 70;
    e.turns.bestScorePct = 97;
    e.turns.bestDryStreak = 12;
    e.pump.successes = 39;
    e.pump.failed = 17;
    e.pump.strokes = 4210;
    e.pump.pumpsSum = 168;
    e.hrCost.lastCostBpm = 19;
    for (var i = 0; i < 300; i++) {
        e.history.tick(1.0, i % 3 != 0, 4.0 + (i % 17));
    }
    for (var i = 0; i < 40; i++) {
        e.history.logTurn(i % 3 + 1);
    }
    // a real breadcrumb: a long thin reach, which is the case that must not be stretched
    e.trackEnabled = true;
    var tLat = new [8] as Array<Float>;
    var tLon = new [8] as Array<Float>;
    var tFly = new [8] as Array<Boolean>;
    for (var i = 0; i < 8; i++) {
        tLat[i] = 45.87 + i * 0.0002;
        tLon[i] = 10.87 + i * 0.0040;
        tFly[i] = i % 3 != 0;
    }
    e.trackLat = tLat;
    e.trackLon = tLon;
    e.trackFly = tFly;
    e.trackN = 8;

    SummaryNav.build(c);
    Test.assertEqual(SummaryNav.count(), 7);
    for (var i = 0; i < SummaryNav.count(); i++) {
        SummaryNav.index = i;
        view.onUpdate(dc);
    }
    // wrapping is total, in both directions, exactly as the recording pages wrap
    Test.assertEqual(SummaryNav.wrap(-1), SummaryNav.count() - 1);
    Test.assertEqual(SummaryNav.wrap(SummaryNav.count()), 0);
    SummaryNav.index = 0;
    SummaryNav.step(-1);
    Test.assertEqual(SummaryNav.index, SummaryNav.count() - 1);
    SummaryNav.step(1);
    Test.assertEqual(SummaryNav.index, 0);

    // a degenerate track (all points identical) must still paint
    for (var i = 0; i < 8; i++) {
        tLat[i] = 45.87;
        tLon[i] = 10.87;
    }
    SummaryNav.build(c);
    for (var i = 0; i < SummaryNav.count(); i++) {
        SummaryNav.index = i;
        view.onUpdate(dc);
    }

    c.engine = saved;
    SummaryNav.build(c);
    SummaryNav.index = 0;
    logger.debug("summary: 4 pages bare, 7 pages full, all painted");
    return true;
}

// ---- Alert debounce ----
// The rule the vibe language depends on: a PB buzz must not swallow the turn outcome that
// lands four seconds later. Coming out of a fast jibe that pair is the NORMAL case, and one
// shared timestamp made the more informative of the two silently disappear.
(:test)
function alertDebounceIsPerChannelNotGlobal(logger as Test.Logger) as Boolean {
    Test.assertEqual(AlertManager.CH_COUNT, 5);
    Test.assertMessage(AlertManager.GLOBAL_FLOOR_MS < AlertManager.DEBOUNCE_MS,
        "the global floor must be shorter than the per-channel window");

    // the case that was broken: PB at t, turn outcome at t + 4 s. Different channels, so the
    // turn's own 5 s window is wide open; only the 1 s floor applies, and 4 s clears it.
    // A channel that has never fired reads 0, which `allows` treats as "buzzed at t = 0" —
    // harmless on a real watch because System.getTimer() is already well past the window by
    // the time anything can alert, and asserted here so that assumption is written down.
    Test.assertMessage(AlertManager.allows(6000, 0, 0), "a fresh channel must fire");
    Test.assertMessage(!AlertManager.allows(4000, 0, 0),
        "the boot window is DEBOUNCE_MS long and that is deliberate");
    Test.assertMessage(AlertManager.allows(104000, 0, 100000),
        "a turn outcome 4 s after a PB was swallowed");

    // ...and the SAME channel repeating inside 5 s must still be suppressed
    Test.assertMessage(!AlertManager.allows(104000, 100000, 100000),
        "the same alert repeated after 4 s must be debounced");
    Test.assertMessage(AlertManager.allows(105000, 100000, 100000),
        "5 s must reopen the channel");

    // total vibes stay bounded: nothing plays within the global floor of anything else
    Test.assertMessage(!AlertManager.allows(100500, 0, 100000),
        "two buzzes 500 ms apart would overlap into mush");
    Test.assertMessage(AlertManager.allows(101000, 0, 100000), "1 s apart is allowed");

    // the live path must not crash, and must leave the channels distinguishable
    AlertManager.reset();
    var pb = AppSettings.alertPb;
    var turn = AppSettings.alertTurn;
    AppSettings.alertPb = true;
    AppSettings.alertTurn = true;
    AlertManager.speedPb();
    AlertManager.turnOutcome(TurnDetector.OUTCOME_TOUCHDOWN);
    AlertManager.longestFlight();
    AlertManager.takeoff();
    AlertManager.interval();
    AppSettings.alertPb = pb;
    AppSettings.alertTurn = turn;
    AlertManager.reset();
    logger.debug("debounce: " + AlertManager.DEBOUNCE_MS.toString() + " ms per channel, "
        + AlertManager.GLOBAL_FLOOR_MS.toString() + " ms global floor");
    return true;
}

// ---- PumpDetector: the attempt join grace ----
// One bout of pumping with a breather in the middle is ONE takeoff attempt, not two. The
// silence that separates two efforts is measured to a burst's FIRST stroke, and a burst that
// opens inside the window is given ATTEMPT_JOIN_GRACE_MS to reach pumpMinStrokes and join —
// without which a rider who pauses to breathe reads as a failed attempt plus a success.
(:test)
function pumpBreatherDoesNotSplitOneAttempt(logger as Test.Logger) as Boolean {
    var r = new PumpRig();
    r.quiet(5);
    r.pump(10);                                   // the lead burst opens the effort
    Test.assertMessage(r.det.attemptOpen(), "the first burst must open an effort");
    var lead = r.det.strokes;

    r.quiet(8);                                   // a breather, inside takeoffAttemptWindow
    Test.assertMessage(r.det.attemptOpen(),
        "the effort must survive 8 s of silence, failed=" + r.det.failed.toString());
    Test.assertEqual(r.det.failed, 0);

    r.pump(6);                                    // back at it: the same effort continues
    Test.assertMessage(r.det.attemptOpen(), "the second burst must join, not open a new one");
    Test.assertEqual(r.det.failed, 0);

    r.flying = true;                              // up on the foil
    r.quiet(3);
    Test.assertEqual(r.confirmFlight(), PumpDetector.EVENT_TAKEOFF);

    Test.assertMessage(r.det.attempts() == 1,
        "a breather split one bout into " + r.det.attempts().toString() + " attempts");
    Test.assertEqual(r.det.successes, 1);
    Test.assertEqual(r.det.failed, 0);
    Test.assertEqual(r.det.successPct(), 100);
    Test.assertMessage(r.det.strokes > lead, "the second burst's strokes must still count");
    logger.debug("breather: " + r.det.strokes.toString() + " strokes over two bursts, "
        + r.det.attempts().toString() + " attempt, " + r.det.failed.toString() + " failed");
    return true;
}

// ---- FIT: the wind-derived session fields ----
// Without a wind axis the classifier calls every sweep a generic turn, so tack_count and
// jibe_count are structurally 0 — and "0 tacks, 0 jibes" is indistinguishable from a rider
// who genuinely never tacked in two hours. Absent is the honest encoding.
(:test)
function fitOmitsTurnCountsWhenNoWindAxisWasSet(logger as Test.Logger) as Boolean {
    var before = AppSettings.cfg.windDirection;
    var wasSet = AppSettings.windEverSet;

    AppSettings.windEverSet = false;
    Test.assertMessage(!FitFields.writesTurnCounts(),
        "no wind axis: tack/jibe/wind_dir must be ABSENT, not 0");

    // setting an axis is what turns them on, through the same path the wind menu uses
    AppSettings.storeWindDirection(225);
    Test.assertEqual(AppSettings.cfg.windDirection, 225);
    Test.assertMessage(AppSettings.windEverSet, "a real bearing must arm the counts");
    Test.assertMessage(FitFields.writesTurnCounts(), "with an axis the counts are written");

    // ...and it is STICKY: clearing the axis afterwards does not unclassify the turns that
    // were already split, it only leaves wind_dir_user at its unset sentinel.
    AppSettings.storeWindDirection(-1);
    Test.assertEqual(AppSettings.cfg.windDirection, -1);
    Test.assertMessage(FitFields.writesTurnCounts(),
        "clearing the axis must not retract counts that were really classified");

    // a rejected push must not arm anything
    AppSettings.windEverSet = false;
    AppSettings.storeWindDirection(400);
    Test.assertMessage(!AppSettings.windEverSet, "an out-of-range bearing armed the counts");
    Test.assertMessage(!FitFields.writesTurnCounts(), "junk must not enable the fields");

    AppSettings.storeWindDirection(before);
    AppSettings.windEverSet = wasSet;
    logger.debug("wind gate: absent without an axis, sticky once set");
    return true;
}

// ---- Release bookkeeping ----
// The FIT's app_version high byte IS the app's minor version. They drifted once (the app was
// 0.7.0 while the byte still said 1) and nothing noticed, because nothing held them together.
(:test)
function appVersionAgreesWithTheFitByte(logger as Test.Logger) as Boolean {
    Test.assertEqual(FitSchema.APP_VERSION, "0.8.0");
    Test.assertEqual(FitSchema.APP_MINOR, 8);
    // the string's minor field, parsed rather than assumed
    var v = FitSchema.APP_VERSION;
    var dot = v.find(".");
    Test.assertMessage(dot != null, "version string has no minor field");
    var rest = v.substring((dot as Number) + 1, v.length());
    var dot2 = rest.find(".");
    Test.assertMessage(dot2 != null, "version string has no patch field");
    var minor = rest.substring(0, dot2 as Number).toNumber();
    Test.assertMessage(minor != null && minor == FitSchema.APP_MINOR,
        "APP_VERSION " + v + " disagrees with APP_MINOR "
            + FitSchema.APP_MINOR.toString());
    // and the packed field the phone reads
    Test.assertEqual(FitSchema.APP_MINOR * 256 + FitSchema.SCHEMA_VERSION, 8 * 256 + 2);
    logger.debug("release " + FitSchema.APP_VERSION + ", app_version byte "
        + (FitSchema.APP_MINOR * 256 + FitSchema.SCHEMA_VERSION).toString());
    return true;
}

// ---- Paging while paused ----
// MapPageView extends the firmware's MapTrackView and cannot be drawn into, so it can show no
// PAUSED banner, no speed, no foil state. A rider who pauses, pages to the map and rides on
// has no indication anywhere that he is not recording — so while paused the map is skipped.
(:test)
function pausedRidersCannotPageOntoTheMap(logger as Test.Logger) as Boolean {
    if (!PageModel.hasMap()) {
        logger.debug("no MapTrackView on this product - rule is vacuous");
        return true;
    }
    // page 1 hero, page 2 map, page 3 clock
    PageModel.build({
        "pg1Layout" => PageModel.LAYOUT_MAIN,
        "pg2Layout" => PageModel.LAYOUT_MAP,
        "pg3Layout" => PageModel.LAYOUT_CLOCK,
        "pg4Layout" => 0, "pg5Layout" => 0, "pg6Layout" => 0
    });
    Test.assertEqual(PageModel.count(), 3);
    Test.assertEqual(PageModel.layoutAt(1), PageModel.LAYOUT_MAP);

    // recording: the map is a page like any other
    Test.assertEqual(PageNav.nextIndex(0, 1, false), 1);
    Test.assertEqual(PageNav.nextIndex(2, 1, false), 0);

    // paused: stepping forward from page 1 lands on page 3, not the map
    Test.assertEqual(PageNav.nextIndex(0, 1, true), 2);
    // ...and backward from page 3 lands on page 1, still skipping it
    Test.assertEqual(PageNav.nextIndex(2, -1, true), 0);

    // a set that is nothing BUT map pages must terminate rather than spin
    PageModel.build({
        "pg1Layout" => PageModel.LAYOUT_MAP,
        "pg2Layout" => PageModel.LAYOUT_MAP,
        "pg3Layout" => 0, "pg4Layout" => 0, "pg5Layout" => 0, "pg6Layout" => 0
    });
    Test.assertEqual(PageNav.nextIndex(0, 1, true), 0);

    PageModel.build({});
    PageNav.index = 0;
    logger.debug("paused: map pages skipped in both directions, all-map config terminates");
    return true;
}

// ---- PbFlash survives paging ----
// PbFlash.mc's own header says state lives in a module because "paging on and off the map
// swaps the whole View, and a celebration must not die because the rider happened to be
// scrolling" — and RecordingView.onHide then called PbFlash.stop(), defeating it four lines
// later. The flash auto-clears at FRAMES, which is what makes leaving it running safe.
(:test)
function pbFlashSurvivesAPageSwap(logger as Test.Logger) as Boolean {
    var view = new RecordingView();
    PbFlash.stop();
    PbFlash.fire(13.7);
    Test.assertMessage(PbFlash.active(), "the flash must be running");
    view.onHide();                                // the rider pages to the next screen
    Test.assertMessage(PbFlash.active(),
        "paging killed the celebration the module exists to protect");
    // it still runs out on its own, which is what makes that safe
    for (var i = 0; i <= PbFlash.FRAMES; i++) {
        PbFlash.tick();
    }
    Test.assertMessage(!PbFlash.active(), "the flash must still clear itself");
    logger.debug("onHide leaves the flash running; it expires after "
        + PbFlash.FRAMES.toString() + " frames");
    return true;
}

// ---- Colour vocabulary (docs/presentation.md) ----
// The finding this guards: the watch used Graphics.COLOR_GREEN for BOTH the phase tint ("he
// is on the foil") and the outcome ladder's "flew through". On the Timeline page those two
// are six rows apart on one screen — foil-fraction bars over turn-outcome dots — so one ink
// was carrying two meanings in the same glance. Asserted on BOTH palettes, because the 8 bpp
// MIP quantisation is exactly where two distinct colours can silently become one.
(:test)
function colourVocabularyIsUnambiguous(logger as Test.Logger) as Boolean {
    var wasMip = Ink.isMip();
    for (var pass = 0; pass < 2; pass++) {
        Ink.forceMip(pass == 1);
        var where = pass == 1 ? " (MIP)" : " (AMOLED)";

        // the ladder's three rungs are three different colours
        Test.assertMessage(Ink.ladderFlew() != Ink.ladderTouchdown(), "flew == touchdown" + where);
        Test.assertMessage(Ink.ladderTouchdown() != Ink.ladderFellIn(), "touch == fell" + where);
        Test.assertMessage(Ink.ladderFlew() != Ink.ladderFellIn(), "flew == fell" + where);
        Test.assertMessage(Ink.ladderNone() != Ink.ladderFlew(), "no verdict == flew" + where);

        // THE rule: a phase is not a verdict
        Test.assertMessage(Ink.phaseFlying() != Ink.ladderFlew(),
            "phase teal and ladder green are the same ink" + where);
        Test.assertMessage(Ink.phaseOffFoil() != Ink.ladderFellIn(),
            "off foil and fell in are the same ink" + where);
        // an effort is not a verdict either: a PB is something he did, not a good jibe
        Test.assertMessage(Ink.effortWindow() != Ink.ladderFlew(),
            "the record ink borrows the ladder's green" + where);
        Test.assertMessage(Ink.effortPumping() != Ink.ladderFellIn(),
            "heart rate is still wearing the ladder's red" + where);
        // ...and the two halves of every two-state mark must be told apart
        Test.assertMessage(Ink.dim() != Ink.phaseFlying(), "off-foil ink == on-foil ink" + where);
    }
    Ink.forceMip(wasMip);

    // the catalog agrees: foil % is a phase, heart rate is not a verdict
    var c = getApp().controller;
    Test.assertEqual(PageModel.color(PageModel.M_FOIL_PCT, c), Ink.phaseFlying());
    Test.assertMessage(PageModel.color(PageModel.M_HR, c) != Ink.ladderFellIn(),
        "heart rate must not be the ladder's red");
    Test.assertEqual(PageModel.color(PageModel.M_SPEED, c), Graphics.COLOR_WHITE);

    // the outcome ladder the pages actually draw with
    Test.assertEqual(RecordingView.outcomeColor(TurnDetector.OUTCOME_FLEW), Ink.ladderFlew());
    Test.assertEqual(RecordingView.outcomeColor(TurnDetector.OUTCOME_TOUCHDOWN),
        Ink.ladderTouchdown());
    Test.assertEqual(RecordingView.outcomeColor(TurnDetector.OUTCOME_FELL), Ink.ladderFellIn());
    Test.assertEqual(RecordingView.outcomeColor(TurnDetector.OUTCOME_NONE), Ink.ladderNone());

    // every token is a real 24-bit literal, not a stray Graphics constant that happens to
    // compare equal to one
    var inks = [DesignTokens.PHASE_FLYING, DesignTokens.PHASE_OFF_FOIL,
        DesignTokens.OUTCOME_FLEW, DesignTokens.OUTCOME_TOUCHDOWN, DesignTokens.OUTCOME_FELL_IN,
        DesignTokens.EFFORT_WINDOW, DesignTokens.EFFORT_PUMPING];
    for (var i = 0; i < inks.size(); i++) {
        Test.assertMessage(inks[i] > 0 && inks[i] <= 0xFFFFFF,
            "token " + i.toString() + " is not an RGB literal");
    }
    // the generated MIP twins really are in the 64-colour palette
    var mips = [DesignTokens.PHASE_FLYING_MIP, DesignTokens.PHASE_OFF_FOIL_MIP,
        DesignTokens.OUTCOME_FLEW_MIP, DesignTokens.OUTCOME_TOUCHDOWN_MIP,
        DesignTokens.OUTCOME_FELL_IN_MIP, DesignTokens.EFFORT_WINDOW_MIP];
    for (var i = 0; i < mips.size(); i++) {
        for (var shift = 0; shift <= 16; shift += 8) {
            var ch = (mips[i] >> shift) & 0xFF;
            Test.assertMessage(ch == 0x00 || ch == 0x55 || ch == 0xAA || ch == 0xFF,
                "MIP token " + i.toString() + " channel " + ch.format("%02x")
                    + " is outside the 8 bpp palette");
        }
    }
    logger.debug("phase " + Ink.phaseFlying().format("%06x") + " vs ladder flew "
        + Ink.ladderFlew().format("%06x") + "; this device is "
        + (Ink.isMip() ? "MIP" : "AMOLED"));
    return true;
}
