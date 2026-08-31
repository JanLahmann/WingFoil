import Toybox.Communications;
import Toybox.Position;
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
    // The session target. It USED to be 15, one below the hard limit, so the next row added
    // tripped a test with room to spare; 0.9.0's wind_dir_auto(44) spent that slot and the
    // target is now the limit itself (FitSchema.SESSION_FIELD_TARGET says why, and says that
    // the next session field has to pack). This assertion is therefore no longer the early
    // warning it was — the one above it is the whole net now.
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

// The Turns page, rebuilt in 0.8.2: header · the TALLY as the giant · both streaks · the
// outcome strip · the verdict with its port/starboard entry split. Five rows on a round glass,
// two of which (the strip and the verdict) live deep in the bottom arc where the chord has
// collapsed to about two thirds of the diameter — which is exactly why they are measured here.
(:test)
function turnsPageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = screenPx() / 2;
    var radius = screenPx() / 2.0 - BEZEL;
    var pageR = RecordingView.fitRadius(dc, false, false);

    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    // the giant's band is its INK height since 0.9.2 — the leading around a pinned font is
    // knowable dead space, and the four rows under it were being pushed down by all of it
    var hG = RecordingView.inkH(dc, Graphics.FONT_NUMBER_MEDIUM);
    var hK = dc.getFontHeight(Graphics.FONT_MEDIUM);
    var hD = RecordingView.stripBandH(dc);
    var hS = dc.getFontHeight(TEXT_FONTS[VERDICT_FROM]);

    // row 0: header, widest with a wind axis set
    // The widest form the header can take: 0.9.0 marks an axis the watch estimated with a
    // leading "~", so the worst case gained a character.
    var header = "tack / jibe  ~NNE";
    var r = cornerRadius(dc.getTextWidthInPixels(header, Graphics.FONT_XTINY), hT,
        RecordingView.turnsRowY(cy, hT, hG, hK, hD, hS, 0), cy);
    Test.assertMessage(r <= radius, "header corner " + r.format("%.0f") + " > " + radius);

    // row 1: the GIANT is the tally itself — flew · touched · swam, three counts in the three
    // ladder colours. Measured at its worst case (three two-digit counts) and at the shipped
    // session's own (35/8/8), because the first says it never clips and the second says the
    // page a rider actually sees is not permanently stepped down.
    var y1 = RecordingView.turnsRowY(cy, hT, hG, hK, hD, hS, 1);
    var gBudget = RecordingView.rowBudget(pageR, y1 - cy,
        RecordingView.inkH(dc, Graphics.FONT_NUMBER_MEDIUM));
    var worstF = RecordingView.giantTallyFont(dc, "99", "99", "99", gBudget);
    r = cornerRadius(RecordingView.giantTallyWidth(dc, "99", "99", "99", worstF),
        RecordingView.inkH(dc, worstF), y1, cy);
    Test.assertMessage(r <= pageR,
        "giant tally corner " + r.format("%.0f") + " > " + pageR.toString());
    // a count is a value: the ladder may step down, never below the readability floor
    Test.assertMessage(dc.getFontHeight(worstF) >= dc.getFontHeight(Graphics.FONT_SMALL),
        "giant tally fell below FONT_SMALL");
    // and it must still be a NUMBER font for the session the app was designed against
    var realF = RecordingView.giantTallyFont(dc, "35", "8", "8", gBudget);
    Test.assertMessage(dc.getFontHeight(realF) >= dc.getFontHeight(Graphics.FONT_NUMBER_MILD),
        "the giant tally is not a giant on a real session");
    r = cornerRadius(RecordingView.giantTallyWidth(dc, "35", "8", "8", realF),
        RecordingView.inkH(dc, realF), y1, cy);
    Test.assertMessage(r <= pageR,
        "giant tally (real) corner " + r.format("%.0f") + " > " + pageR.toString());
    // the separator is a drawn dot, not punctuation — the number fonts have none — so its
    // slot has to scale with whatever font the row landed in
    Test.assertMessage(RecordingView.giantSepW(dc, realF) > RecordingView.giantSepR(dc, realF),
        "the separator dot does not fit its own slot");
    Test.assertMessage(
        RecordingView.giantTallyWidth(dc, "9", "9", "9", realF)
            < RecordingView.giantTallyWidth(dc, "99", "99", "99", realF),
        "one-digit counts are not narrower than two-digit ones");
    logger.debug("turns giant: worst " + dc.getFontHeight(worstF).toString() + "px, real "
        + dc.getFontHeight(realF).toString() + "px (NUMBER_MEDIUM is " + hG.toString() + ")");

    // row 2: BOTH streaks — "streak: 99/99  99/99". ONE grey caption for the row now, the two
    // runs told apart by the ladder's own inks rather than by two words. Worst case is four
    // two-digit numbers, and it is strictly narrower than the two-caption row it replaced.
    var y2 = RecordingView.turnsRowY(cy, hT, hG, hK, hD, hS, 2);
    var kBudget = RecordingView.rowBudget(pageR, y2 - cy,
        RecordingView.inkH(dc, Graphics.FONT_MEDIUM));
    var kf = RecordingView.streakRow2Font(dc, "99", "99", "99", "99", kBudget, true);
    r = cornerRadius(RecordingView.streakRow2Width(dc, "99", "99", "99", "99", kf, true),
        RecordingView.inkH(dc, kf), y2, cy);
    Test.assertMessage(r <= pageR,
        "streak row corner " + r.format("%.0f") + " > " + pageR.toString());
    Test.assertMessage(dc.getFontHeight(kf) >= dc.getFontHeight(Graphics.FONT_SMALL),
        "streak row fell below FONT_SMALL");
    // the post-save form drops "the run he is on" and must be narrower for it
    Test.assertMessage(
        RecordingView.streakRow2Width(dc, "99", "99", "99", "99", kf, false)
            < RecordingView.streakRow2Width(dc, "99", "99", "99", "99", kf, true),
        "dropping the live run must save width");

    // row 3: the outcome strip. It is a texture, not a census — it shows the most recent dots
    // that fit — so what is asserted is that the band it reserves clears the glass and that a
    // long session really does drop the oldest rather than overflow.
    var y3 = RecordingView.turnsRowY(cy, hT, hG, hK, hD, hS, 3);
    var stripW = RecordingView.rowBudget(pageR, y3 - cy, hD);
    var shown = RecordingView.dotsShown(64, stripW);
    Test.assertMessage(shown >= 8,
        "the strip row holds only " + shown.toString() + " dots");
    Test.assertMessage(shown <= 64, "the strip claims more dots than the log holds");
    var pitch = 2 * TL_DOT_R + TL_DOT_GAP;
    r = cornerRadius(shown * pitch - TL_DOT_GAP, 2 * TL_DOT_R, y3, cy);
    Test.assertMessage(r <= pageR,
        "strip corner " + r.format("%.0f") + " > " + pageR.toString());
    Test.assertEqual(RecordingView.dotsShown(3, stripW), 3);   // short sessions show them all

    // row 4: the verdict and the port/starboard entry split, at its widest — "100% flew" with
    // two two-digit side counts. The word grew by two glyphs in 0.8.2 (the row now prints the
    // flew-through share, which agrees with the tally above it by construction), so the 416 px
    // assertion below is exactly the one that had to be re-measured. The P/S half is DROPPED
    // rather than shrunk when it does not fit, so the assertion is on whichever form the
    // renderer would actually choose.
    // The row's values step down from TEXT_FONTS[VERDICT_FROM] (0.9.2 — they used to be pinned
    // at the FONT_SMALL floor on a row that had already been given a FONT_MEDIUM band), and
    // whether the P/S half is kept is decided at the FLOOR: content first, then size.
    var y4 = RecordingView.turnsRowY(cy, hT, hG, hK, hD, hS, 4);
    var floorF = TEXT_FONTS[TALLY_FLOOR];
    var vBudget = RecordingView.rowBudget(pageR, y4 - cy,
        RecordingView.inkH(dc, TEXT_FONTS[VERDICT_FROM]));
    var sides = RecordingView.verdictWidth(dc, "100", "99", "99", true, floorF) <= vBudget;
    var vf = RecordingView.verdictFont(dc, "100", "99", "99", sides, vBudget);
    r = cornerRadius(RecordingView.verdictWidth(dc, "100", "99", "99", sides, vf),
        RecordingView.inkH(dc, vf), y4, cy);
    Test.assertMessage(r <= pageR,
        "verdict corner " + r.format("%.0f") + " > " + pageR.toString());
    Test.assertMessage(dc.getFontHeight(vf) >= dc.getFontHeight(floorF),
        "the verdict row fell below the readability floor");
    Test.assertMessage(dc.getFontHeight(vf) <= hS,
        "the verdict row is taller than the band it was stacked with");
    // the verdict alone must ALWAYS fit: it is the row's reason to exist
    Test.assertMessage(RecordingView.verdictWidth(dc, "100", "99", "99", false, floorF)
        <= vBudget, "not even '100% flew' fits the verdict row");
    // ...and on the two AMOLED variants the SIDE SPLIT must survive too. It is the only
    // number on the page the rider can act on tomorrow, and it was being dropped on the 43 mm
    // glass by three spaces (" % ok", "P ", " / ") that carried no information.
    if (screenPx() >= 416) {
        Test.assertMessage(
            RecordingView.verdictWidth(dc, "49", "29", "22", true, floorF) <= vBudget,
            "the port/starboard split does not fit a "
                + screenPx().toString() + "px glass: "
                + RecordingView.verdictWidth(dc, "49", "29", "22", true, floorF).toString()
                + "px of " + vBudget.toString());
    }
    Test.assertMessage(RecordingView.verdictWidth(dc, "49", "29", "22", false, floorF)
        < RecordingView.verdictWidth(dc, "49", "29", "22", true, floorF),
        "dropping the side split must save width");
    // a wider font is a wider row: the ladder has to be monotonic or stepping down is not a fix
    Test.assertMessage(
        RecordingView.verdictWidth(dc, "49", "29", "22", true, floorF)
            <= RecordingView.verdictWidth(dc, "49", "29", "22", true,
                TEXT_FONTS[VERDICT_FROM]),
        "the verdict row does not get narrower as its font does");
    logger.debug("verdict row: "
        + RecordingView.verdictWidth(dc, "49", "29", "22", true, vf).toString() + "px of "
        + vBudget.toString() + " at font height " + dc.getFontHeight(vf).toString()
        + " (floor " + dc.getFontHeight(floorF).toString() + "), sides "
        + (sides ? "on" : "dropped"));

    // the rows must not collide, and the block must be centred
    var y0 = RecordingView.turnsRowY(cy, hT, hG, hK, hD, hS, 0);
    Test.assertMessage(y1 - y0 >= (hT + hG) / 2, "header/giant gap");
    Test.assertMessage(y2 - y1 >= (hG + hK) / 2, "giant/streak gap");
    Test.assertMessage(y3 - y2 >= (hK + hD) / 2, "streak/strip gap");
    Test.assertMessage(y4 - y3 >= (hD + hS) / 2, "strip/verdict gap");
    Test.assertMessage((((cy - (y0 - hT / 2)) - ((y4 + hS / 2) - cy)).abs() <= 1),
        "turns block off centre: " + (cy - (y0 - hT / 2)).toString() + " vs "
            + ((y4 + hS / 2) - cy).toString());
    logger.debug("turns page rows y=" + y0.toString() + "," + y1.toString() + ","
        + y2.toString() + "," + y3.toString() + "," + y4.toString());
    return true;
}

// The tally block on the MAIN page — three counts, optional separators, optional verdict —
// keeps its own rules: it sheds CONTENT rather than dropping below FONT_SMALL, because the
// session whose tally is widest (30+ turns, three two-digit counts) is exactly the session
// whose tally the rider wants to read.
(:test)
function tallyRowShedsContentNotSize(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = screenPx() / 2;
    var pageR = RecordingView.fitRadius(dc, false, false);
    var hC = dc.getFontHeight(Graphics.FONT_NUMBER_MILD);
    var hN = RecordingView.inkH(dc, Graphics.FONT_NUMBER_MEDIUM);
    var hD = RecordingView.stripBandH(dc);
    var hO = dc.getFontHeight(Graphics.FONT_LARGE);
    var hK = dc.getFontHeight(Graphics.FONT_MEDIUM);
    var y = RecordingView.mainRowY(cy, hC, hN, hD, hO, hK, 3);
    var budget = RecordingView.rowBudget(pageR, y - cy,
        RecordingView.inkH(dc, Graphics.FONT_LARGE));

    var tallyF = RecordingView.tallyFont(dc, "99", "99", "99", "100% flew", budget, 0);
    Test.assertMessage(dc.getFontHeight(tallyF) >= dc.getFontHeight(Graphics.FONT_SMALL),
        "the tally stepped below the readability floor");
    var mask = RecordingView.tallyContent(dc, "99", "99", "99", "100% flew", budget, tallyF);
    Test.assertMessage(mask >= 0, "not even three bare counts fit the tally row");
    var ok = (mask & TALLY_OK) != 0 ? "100% flew" : "";
    var sep = (mask & TALLY_SEPARATORS) != 0 ? TURNS_TALLY_SEP : TALLY_SEP_NARROW;
    var r = cornerRadius(RecordingView.tallyWidth(dc, "99", "99", "99", ok, sep, tallyF),
        RecordingView.inkH(dc, tallyF), y, cy);
    Test.assertMessage(r <= pageR,
        "tally corner " + r.format("%.0f") + " > " + pageR.toString());

    // ...and dropping content must actually be cheaper than keeping it, in that order
    Test.assertMessage(
        RecordingView.tallyWidth(dc, "99", "99", "99", "", TURNS_TALLY_SEP, tallyF)
            < RecordingView.tallyWidth(dc, "99", "99", "99", "100% flew", TURNS_TALLY_SEP,
                tallyF), "dropping the verdict must save width");
    Test.assertMessage(
        RecordingView.tallyWidth(dc, "99", "99", "99", "", TALLY_SEP_NARROW, tallyF)
            < RecordingView.tallyWidth(dc, "99", "99", "99", "", TURNS_TALLY_SEP, tallyF),
        "dropping the separators must save width");

    // The share is the FLEW-THROUGH share — the green count over the counted turns, so it is
    // derivable from the tally beside it — and it stays empty until there is a turn to divide
    // by. (The carried-speed success score left the watch in 0.8.2; it lives in the phone
    // analysis, where a number that mixes speed retention into an outcome belongs.)
    Test.assertEqual(RecordingView.flewText(0, 0), "");
    Test.assertEqual(RecordingView.flewText(2, 1), "50% flew");
    Test.assertEqual(RecordingView.flewText(3, 3), "100% flew");
    Test.assertEqual(RecordingView.flewText(51, 35), "68% flew");
    logger.debug("main tally at font height " + dc.getFontHeight(tallyF).toString()
        + ", content mask " + mask.toString());
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
    // the giant's band is its INK height (0.9.2): the 53 px of THAI_HOT leading on a 454 px
    // glass was pushing the unit line and both sub-rows deeper into the narrowing chord
    var hN = RecordingView.inkH(dc, Graphics.FONT_NUMBER_THAI_HOT);
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
    var bigCells = 0;
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

        // CELLS2 reuses the cell row at the widest depth on the screen, and since 0.9.2 it
        // reserves a FONT_NUMBER_MILD band and fits through the NUMBER ladder: two numbers on
        // a whole 454 px glass were spending 76 % of it on nothing. The ladder still steps
        // down into the text fonts for the strings MILD cannot hold in half a chord, so what
        // is asserted is the FLOOR — never worse than the FONT_LARGE it used to be pinned at.
        var hC2 = RecordingView.cellValueBand(dc, true);
        var inkC2 = RecordingView.inkH(dc, RecordingView.cellValueFont(true));
        var y2 = RecordingView.cells2RowY(cy, hT, hC2) + (hT + hC2) / 2;
        var c2 = RecordingView.cellColumns(radius, y2 - cy, inkC2);
        var f2 = RecordingView.cellValueFit(dc, v, 2 * c2[1], true);
        r = cornerRadiusAt(cx, cx + c2[0], dc.getTextWidthInPixels(v, f2),
            RecordingView.inkH(dc, f2), y2, cy);
        Test.assertMessage(r <= limit,
            "cells2 value m" + m.toString() + " r=" + r.format("%.0f") + " > " + limit);
        Test.assertMessage(dc.getFontHeight(f2) >= dc.getFontHeight(Graphics.FONT_LARGE),
            "cells2 value m" + m.toString() + " is smaller than the FONT_LARGE it replaced");
        Test.assertMessage(RecordingView.inkH(dc, f2) <= hC2,
            "cells2 value m" + m.toString() + " is taller than its own band");
        if (dc.getFontHeight(f2) >= dc.getFontHeight(Graphics.FONT_NUMBER_MILD)) { bigCells++; }
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
    // The CELLS2 bump has to actually buy something. These are WORST-case strings — a 199:59
    // timer, a 99>99 takeoff split — so not every metric can reach the number ladder in half a
    // chord, and the ones that cannot render exactly as they did before. What must reach it is
    // a third of the catalogue and, specifically, a speed: the number a two-cell page is for.
    Test.assertMessage(bigCells >= PageModel.M_MAX / 3,
        "only " + bigCells.toString() + " of " + PageModel.M_MAX.toString()
            + " metrics reach FONT_NUMBER_MILD in a CELLS2 cell");
    var hC2f = RecordingView.cellValueBand(dc, true);
    var y2f = RecordingView.cells2RowY(cy, hT, hC2f) + (hT + hC2f) / 2;
    var c2f = RecordingView.cellColumns(radius, y2f - cy,
        RecordingView.inkH(dc, RecordingView.cellValueFont(true)));
    Test.assertMessage(dc.getFontHeight(RecordingView.cellValueFit(dc,
            PageModel.worstValue(PageModel.M_SPEED), 2 * c2f[1], true))
        >= dc.getFontHeight(Graphics.FONT_NUMBER_MILD),
        "a speed does not reach FONT_NUMBER_MILD in a CELLS2 cell");
    logger.debug("grid: narrowest cell budget " + narrowest.toString() + "px; cells2 "
        + bigCells.toString() + " of " + PageModel.M_MAX.toString() + " at MILD or better");
    return true;
}

// The GRID4 PAIR BAND — the shipped Session page's top row since 0.8.2: foil time % beside
// foil dist %, each under its own word, both inside the band the single giant used to own.
// Measured at the worst case the fitter can be handed ("100%" on both sides plus the captions)
// and at the shipped session's own numbers, on this device's glass, with the foil-% arc on the
// page — which it always is, since foil % is what opens the band in the first place.
(:test)
function gridPairBandFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cx = screenPx() / 2;
    var cy = screenPx() / 2;
    var radius = RecordingView.fitRadius(dc, false, true);
    var limit = radius.toFloat();
    var hG = dc.getFontHeight(Graphics.FONT_NUMBER_MILD);
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hL = dc.getFontHeight(Graphics.FONT_LARGE);
    var bias = RecordingView.gridBias(dc);
    var y = RecordingView.gridRowY(cy, hG, hT, hL, 0, true, bias);

    // the convention: foil % opens the band with the distance share, and nothing else opens
    // one. A rider who puts the distance share in a giant slot gets the single metric he asked
    // for, which is what keeps a re-configured page out of a state the renderer has no rule for.
    Test.assertEqual(PageModel.bandPartner(PageModel.M_FOIL_PCT), PageModel.M_FOIL_DIST_PCT);
    Test.assertEqual(PageModel.bandPartner(PageModel.M_FOIL_DIST_PCT), PageModel.M_NONE);
    for (var m = 1; m <= PageModel.M_MAX; m++) {
        Test.assertMessage(m == PageModel.M_FOIL_PCT
            || PageModel.bandPartner(m) == PageModel.M_NONE,
            "metric " + m.toString() + " opens a pair band nobody designed");
    }
    var lc = PageModel.bandCaption(PageModel.M_FOIL_PCT);
    var rc = PageModel.bandCaption(PageModel.M_FOIL_DIST_PCT);
    Test.assertMessage(!lc.equals(rc) && lc.length() > 0 && rc.length() > 0,
        "the two halves must not share a caption");

    var worst = PageModel.worstValue(PageModel.M_FOIL_PCT);
    Test.assertEqual(worst, PageModel.worstValue(PageModel.M_FOIL_DIST_PCT));
    var f = RecordingView.pairFont(dc, worst, lc, worst, rc, hG, radius, y, cy);

    // a value in a label font is not a value: FONT_MEDIUM is the floor for this band
    Test.assertMessage(dc.getFontHeight(f) >= dc.getFontHeight(Graphics.FONT_MEDIUM),
        "pair band fell below FONT_MEDIUM");
    // ...the block must fit the band the single giant reserved, or it would push the 2x2 down
    // and take the bottom row's corners off the glass...
    Test.assertMessage(RecordingView.pairBandHeight(dc, f) <= hG,
        "pair band is " + RecordingView.pairBandHeight(dc, f).toString()
            + "px tall in a " + hG.toString() + "px band");
    // ...and the font the renderer picked must be one that actually fits, by the renderer's
    // own three-part rule
    Test.assertMessage(
        RecordingView.pairFits(dc, worst, lc, worst, rc, f, hG, radius, y, cy),
        "the fitter returned a font that does not fit");
    var dx = RecordingView.pairColumn(dc, f, radius, y, cy);
    var wl = RecordingView.pairHalfWidth(dc, worst, lc, f);
    var wr = RecordingView.pairHalfWidth(dc, worst, rc, f);
    var yCap = RecordingView.pairRowY(dc, y, f, 0);
    var yVal = RecordingView.pairRowY(dc, y, f, 1);

    // both halves, both of their rows, each measured at its own depth and its own column
    var caps = [lc, rc];
    var halves = [wl, wr];
    for (var i = 0; i < 2; i++) {
        var r = cornerRadiusAt(cx, cx + dx,
            dc.getTextWidthInPixels(caps[i], Graphics.FONT_XTINY),
            RecordingView.inkH(dc, Graphics.FONT_XTINY), yCap, cy);
        Test.assertMessage(r <= limit, "pair caption " + i.toString() + " r="
            + r.format("%.0f") + " > " + limit);
        r = cornerRadiusAt(cx, cx + dx, halves[i], RecordingView.inkH(dc, f), yVal, cy);
        Test.assertMessage(r <= limit, "pair value " + i.toString() + " r="
            + r.format("%.0f") + " > " + limit);
    }
    // the two halves must not touch — the column split keeps the grid's own gutter between
    // them, exactly as it does for the cells below
    for (var i = 0; i < 2; i++) {
        Test.assertMessage(dx - halves[i] / 2 >= CELL_GUTTER / 2,
            "pair half " + i.toString() + " overflows its column: " + halves[i].toString()
                + "px at dx " + dx.toString());
    }
    // the block must clear the cell row under it and stay inside its own band above
    var yCell = RecordingView.gridRowY(cy, hG, hT, hL, 1, true, bias);
    Test.assertMessage(yVal + RecordingView.inkH(dc, f) / 2 <= yCell - hT / 2,
        "the pair band's digits reach into the first cell row");
    Test.assertMessage(yCap - hT / 2 >= y - hG / 2,
        "the pair band's caption reaches above its own band");

    // the session the app was designed against must not be permanently stepped down: two
    // two-digit shares are what a rider actually sees, and they may never be SMALLER than the
    // three-digit worst case the fitter is asserted on above.
    var realF = RecordingView.pairFont(dc, "56%", lc, "61%", rc, hG, radius, y, cy);
    Test.assertMessage(dc.getFontHeight(realF) >= dc.getFontHeight(f),
        "a real session's band is smaller than the worst case");
    Test.assertMessage(RecordingView.pairFits(dc, "56%", lc, "61%", rc, realF, hG,
        radius, y, cy), "the shipped session's own band does not fit");
    // ...and shorter numbers must SPREAD, not huddle: the columns are fixed, so the gap
    // between the two readings is what grows.
    // (the gap between the two readings is 2*dx minus the two inner half-widths)
    var realDx = RecordingView.pairColumn(dc, realF, radius, y, cy);
    var realGap = 2 * realDx - (RecordingView.pairHalfWidth(dc, "56%", lc, realF)
        + RecordingView.pairHalfWidth(dc, "61%", rc, realF)) / 2;
    Test.assertMessage(realGap > 2 * dx - (wl + wr) / 2,
        "a short pair does not read wider apart than the worst case");
    // a half is never narrower than its own caption
    Test.assertMessage(RecordingView.pairHalfWidth(dc, "0%", lc, f)
        >= dc.getTextWidthInPixels(lc, Graphics.FONT_XTINY),
        "a one-digit half is narrower than the word under it");
    logger.debug("pair band: halves " + wl.toString() + "/" + wr.toString()
        + "px in a " + (2 * RecordingView.cellColumns(radius, yVal - cy,
            RecordingView.inkH(dc, f))[1]).toString() + "px column at dx " + dx.toString()
        + ", font height " + dc.getFontHeight(f).toString() + " (MILD band is "
        + hG.toString() + "), block " + RecordingView.pairBandHeight(dc, f).toString()
        + "px; worst-case gap " + (2 * dx - (wl + wr) / 2).toString()
        + "px, real session gap " + realGap.toString() + "px");
    return true;
}

// The FOIL page — the shipped page 2 since 0.8.2. A titled 3x2 table: "foil" over the "min" /
// "km" column headers, then the two shares, the two totals and the two bests. Measured at the
// worst case the fitter can be handed (100 % on both shares, a 199:59 foil time, 99.9 km) and
// again at the shipped session's own numbers, on this device's glass, with the foil-% arc on
// the page — which it always is, since the page draws it by being the foil page.
(:test)
function foilPageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cx = screenPx() / 2;
    var cy = screenPx() / 2;
    var radius = RecordingView.fitRadius(dc, false, true);
    var limit = radius.toFloat();
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hV = dc.getFontHeight(Graphics.FONT_LARGE);
    var inkT = RecordingView.inkH(dc, Graphics.FONT_XTINY);

    // ---- the stack: title, three value rows, column headers UNDER them, none touching ----
    // The headers moved below the matrix in 0.9.2 and the block stopped being lifted; the
    // three value rows are now symmetric about the equator, which is the widest they can be.
    var y = [RecordingView.foilRowY(cy, hT, hV, 0),
        RecordingView.foilRowY(cy, hT, hV, 1),
        RecordingView.foilRowY(cy, hT, hV, 2),
        RecordingView.foilRowY(cy, hT, hV, 3),
        RecordingView.foilRowY(cy, hT, hV, 4)];
    Test.assertMessage(y[1] - y[0] >= (hT + hV) / 2, "foil title and the share row overlap");
    Test.assertMessage(y[2] - y[1] >= hV && y[3] - y[2] >= hV, "foil value rows overlap");
    Test.assertMessage(y[4] - y[3] >= (hV + hT) / 2, "foil headers and the bests row overlap");
    // the block is CENTRED — no bias of any kind survives
    Test.assertMessage(((cy - (y[0] - hT / 2)) - ((y[4] + hT / 2) - cy)).abs() <= 1,
        "foil block off centre: " + (cy - (y[0] - hT / 2)).toString() + " vs "
            + ((y[4] + hT / 2) - cy).toString());
    // ...and the middle value row sits ON the equator, which is the whole point of the move
    Test.assertMessage((y[2] - cy).abs() <= hV / 2,
        "the foil matrix is not centred on the equator");

    // ---- the table's fixed columns ----
    var half = RecordingView.foilTableHalf(dc, radius, cy, hT, hV);
    // the session the page is really about decides which row keys it can afford (see
    // foilKeys); the worst case is checked against the floor separately below
    var wide = RecordingView.foilWidest(dc, ["63:24", "14.1", "7:04", "2.2"]);
    var keys = RecordingView.foilKeys(dc, half, wide);
    var keyW = RecordingView.foilKeyWidth(dc, half, wide);
    var col = RecordingView.foilColumns(cx, half, keyW);
    Test.assertMessage(col[3] > 0, "the key column ate the whole table");
    // the two value columns keep the grid's own gutter, and the key column clears them both
    Test.assertMessage(col[2] - col[1] >= col[3] + CELL_GUTTER, "foil columns overlap");
    Test.assertMessage(col[1] - col[3] / 2 >= col[0] + keyW + 1,
        "a row key runs into the first column");
    // ...and the block is centred as a WHOLE, key column included
    Test.assertMessage(((cx - col[0]) - ((col[2] + col[3] / 2) - cx)).abs() <= 2,
        "foil table off centre: the key column pushed the numbers sideways");

    // ---- the worst case the page can be handed ----
    // It gets its OWN columns: the key words are chosen from the values the page is about to
    // print, so a worst-case session may be laid out differently from a real one. Both have
    // to fit, which is what these two column sets are.
    var pct = PageModel.worstValue(PageModel.M_FOIL_PCT);           // "100%"
    var tim = PageModel.worstValue(PageModel.M_FOIL_TIME);          // "199:59"
    var km = PageModel.worstValue(PageModel.M_DISTANCE);            // "99.9"
    var wideW = RecordingView.foilWidest(dc, [tim, km, tim, km]);
    var keysW = RecordingView.foilKeys(dc, half, wideW);
    var colW = RecordingView.foilColumns(cx, half,
        RecordingView.foilKeyWidth(dc, half, wideW));
    var fP = RecordingView.foilFont(dc, [pct, pct], colW[3]);
    var fV = RecordingView.foilFont(dc, [tim, km, tim, km], colW[3]);
    // a value in a label font is not a value
    Test.assertMessage(dc.getFontHeight(fP) >= dc.getFontHeight(Graphics.FONT_SMALL)
        && dc.getFontHeight(fV) >= dc.getFontHeight(Graphics.FONT_SMALL),
        "a foil row fell below FONT_SMALL");
    // ...and the row that reserved the band may never be taller than it
    Test.assertMessage(dc.getFontHeight(fP) <= hV && dc.getFontHeight(fV) <= hV,
        "a foil value row is taller than the band it was stacked with");
    // the worst case must fit its column, or the two numbers would run together
    Test.assertMessage(dc.getTextWidthInPixels(tim, fV) <= colW[3]
        && dc.getTextWidthInPixels(km, fV) <= colW[3],
        "the worst-case foil value overflows its column at " + colW[3].toString() + "px");
    Test.assertMessage(dc.getTextWidthInPixels(pct, fP) <= colW[3],
        "the worst-case share overflows its column");

    // ---- every box, at its own depth and its own column, inside the glass ----
    var r = cornerRadius(dc.getTextWidthInPixels(FOIL_TITLE, Graphics.FONT_XTINY), inkT,
        y[0], cy);
    Test.assertMessage(r <= limit, "foil title r=" + r.format("%.0f") + " > " + limit);
    // the column headers, on the BOTTOM row now, where the chord is at its narrowest on this
    // page — which is exactly why a two-word label row is what belongs there
    var hdr = [FOIL_COL_TIME, FOIL_COL_DIST];
    for (var i = 0; i < 2; i++) {
        r = cornerRadiusAt(cx, col[1 + i], dc.getTextWidthInPixels(hdr[i],
            Graphics.FONT_XTINY), inkT, y[4], cy);
        Test.assertMessage(r <= limit, "foil header " + i.toString() + " r="
            + r.format("%.0f") + " > " + limit);
    }
    var rows = [[pct, pct], [tim, km], [tim, km]];
    var fonts = [fP, fV, fV];
    for (var row = 0; row < 3; row++) {
        var ink = RecordingView.inkH(dc, fonts[row]);
        for (var i = 0; i < 2; i++) {
            r = cornerRadiusAt(cx, colW[1 + i],
                dc.getTextWidthInPixels(rows[row][i], fonts[row]), ink, y[1 + row], cy);
            Test.assertMessage(r <= limit, "foil value r" + row.toString() + "c"
                + i.toString() + " r=" + r.format("%.0f") + " > " + limit);
        }
    }
    for (var i = 0; i < 2; i++) {
        var wk = dc.getTextWidthInPixels(keysW[i], Graphics.FONT_XTINY);
        r = cornerRadiusAt(cx, colW[0] + wk / 2, wk, inkT, y[2 + i], cy);
        Test.assertMessage(r <= limit, "foil key " + keysW[i] + " r=" + r.format("%.0f")
            + " > " + limit);
    }
    // the two keys must not read as one word, and must say which row they key
    Test.assertMessage(!keys[0].equals(keys[1]) && keys[0].length() > 0
        && keys[1].length() > 0, "the two row keys must differ");

    // ---- the session the app was designed against ----
    // 56 % / 61 % of a 63:24 / 14.1 km foil session, best flight 7:04 / 2.2 km. Real numbers
    // must never be SMALLER than the three-digit worst case asserted above.
    var realP = RecordingView.foilFont(dc, ["56%", "61%"], col[3]);
    var realV = RecordingView.foilFont(dc, ["63:24", "14.1", "7:04", "2.2"], col[3]);
    Test.assertMessage(dc.getFontHeight(realP) >= dc.getFontHeight(fP)
        && dc.getFontHeight(realV) >= dc.getFontHeight(fV),
        "a real session's foil table is smaller than the worst case");
    // 0.9.2's whole point: the shipped session's six numbers are FONT_LARGE, the top of the
    // value ladder. Before the headers moved below the matrix they were FONT_MEDIUM.
    Test.assertMessage(dc.getFontHeight(realV) >= dc.getFontHeight(Graphics.FONT_LARGE)
        && dc.getFontHeight(realP) >= dc.getFontHeight(Graphics.FONT_LARGE),
        "the foil matrix did not reach FONT_LARGE on a real session: shares "
            + dc.getFontHeight(realP).toString() + ", values "
            + dc.getFontHeight(realV).toString() + " in a " + col[3].toString()
            + "px column");
    // the header says "time", not a unit the cells never print
    Test.assertEqual(FOIL_COL_TIME, "time");
    // the km column is ON-FOIL distance, so it is formatted from metres like any other
    Test.assertEqual(RecordingView.foilKm(14091.0), "14.1");
    Test.assertEqual(RecordingView.foilKm(2249.0), "2.2");
    Test.assertEqual(RecordingView.foilKm(0.0), "0.0");

    logger.debug("foil table: half " + half.toString() + "px, key \"" + keys[0] + "\" "
        + keyW.toString() + "px, columns " + col[3].toString() + "px at "
        + col[1].toString() + "/" + col[2].toString() + "; share row font height "
        + dc.getFontHeight(fP).toString() + ", value rows "
        + dc.getFontHeight(fV).toString() + " (band " + hV.toString()
        + ", LARGE/MED/SMALL " + dc.getFontHeight(Graphics.FONT_LARGE).toString() + "/"
        + dc.getFontHeight(Graphics.FONT_MEDIUM).toString() + "/"
        + dc.getFontHeight(Graphics.FONT_SMALL).toString() + "); real session "
        + dc.getFontHeight(realP).toString() + "/" + dc.getFontHeight(realV).toString());
    return true;
}

// CLOCK page: giant time of day over one configurable cell.
//
// 0.9.2 made the cell a FONT_NUMBER_MILD one (the rider asked for a bigger timer) and paid for
// it out of the giant's leading plus a downward lift of the block. Both halves of that trade
// are asserted here: the giant must KEEP the top of the number ladder, and the cell must
// actually reach the rung it was widened for.
(:test)
function clockPageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = screenPx() / 2;
    var radius = RecordingView.fitRadius(dc, false, false);
    var limit = radius.toFloat();
    var inkN = RecordingView.inkH(dc, Graphics.FONT_NUMBER_THAI_HOT);
    var hN = inkN;                                  // the giant's band IS its ink now
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hV = RecordingView.cellValueBand(dc, true);
    var inkV = RecordingView.inkH(dc, RecordingView.cellValueFont(true));
    var bias = RecordingView.clockBias(dc);

    var y = RecordingView.clockRowY(cy, hN, hT, hV, 0, bias);
    var f = RecordingView.fitFont(dc, NUMBER_FONTS, 0, "23:59",
        RecordingView.rowBudget(radius, y - cy, inkN));
    var r = cornerRadius(dc.getTextWidthInPixels("23:59", f), RecordingView.inkH(dc, f), y, cy);
    Test.assertMessage(r <= limit, "clock giant r=" + r.format("%.0f") + " > " + limit);
    // the lift exists so the clock keeps THAI_HOT despite the taller cell under it
    Test.assertEqual(f, Graphics.FONT_NUMBER_THAI_HOT);
    Test.assertMessage(bias > 0, "the clock block is not lifted at all");

    var yl = RecordingView.clockRowY(cy, hN, hT, hV, 1, bias);
    // the cell's label must clear the giant's INK, which is what the band was cut down to
    Test.assertMessage(yl - hT / 2 >= y + inkN / 2 - 1,
        "the clock cell's label overlaps the giant's digits");
    var yv = yl + (hT + hV) / 2;
    var budget = RecordingView.rowBudget(radius, yv - cy, inkV);
    var big = 0;
    for (var m = 1; m <= PageModel.M_MAX; m++) {
        var v = PageModel.worstValue(m);
        var vf = RecordingView.cellValueFit(dc, v, budget, true);
        Test.assertMessage(dc.getFontHeight(vf) >= dc.getFontHeight(Graphics.FONT_LARGE),
            "clock cell m" + m.toString() + " is smaller than the FONT_LARGE it replaced");
        Test.assertMessage(RecordingView.inkH(dc, vf) <= hV,
            "clock cell m" + m.toString() + " is taller than its band");
        r = cornerRadius(dc.getTextWidthInPixels(v, vf), RecordingView.inkH(dc, vf), yv, cy);
        Test.assertMessage(r <= limit,
            "clock cell m" + m.toString() + " r=" + r.format("%.0f") + " > " + limit);
        if (dc.getFontHeight(vf) >= dc.getFontHeight(Graphics.FONT_NUMBER_MILD)) { big++; }
    }
    // the default cell is the session TIMER, and it is the one this page was widened for
    var tf = RecordingView.cellValueFit(dc, PageModel.worstValue(PageModel.M_TIMER), budget,
        true);
    Test.assertMessage(dc.getFontHeight(tf) >= dc.getFontHeight(Graphics.FONT_NUMBER_MILD),
        "the clock page's timer did not reach FONT_NUMBER_MILD: "
            + dc.getFontHeight(tf).toString() + " in a " + budget.toString() + "px row");
    logger.debug("clock giant font height " + dc.getFontHeight(f).toString()
        + " (THAI_HOT is " + dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT).toString()
        + ", lift " + bias.toString() + "), cell budget " + budget.toString() + "px, "
        + big.toString() + " of " + PageModel.M_MAX.toString() + " metrics at MILD");
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
    // The three band captions. They grew in 0.8.2 — "on foil" became "on foil %" and "speed"
    // became "top speed", because a bar chart with one rail says "more is more" and a max-per-
    // slot sparkline labelled "speed" reads as an average. Both are XTINY labels sitting at
    // shallower depths than the bands they name, but the widest of them is measured here so a
    // future rewording cannot quietly run off the glass.
    var caps = ["on foil %", "top speed km/h", "turns"];
    var capRows = [0, 2, 4];
    for (var i = 0; i < caps.size(); i++) {
        var yc = RecordingView.timelineRowY(cy, hT, strip, spark, capRows[i]);
        r = cornerRadius(dc.getTextWidthInPixels(caps[i], Graphics.FONT_XTINY),
            RecordingView.inkH(dc, Graphics.FONT_XTINY), yc, cy);
        Test.assertMessage(r <= limit,
            "timeline caption '" + caps[i] + "' r=" + r.format("%.0f") + " > " + limit);
    }
    // the strip's two rails span the same chord, so the band reads as a 0-100 % envelope
    Test.assertMessage(
        RecordingView.bandHalfWidth(radius, yStripTop, yStripTop + strip, cy) == hwStrip,
        "the strip's rails do not share one chord");
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

// START page: title, GPS state, wind axis, hint. It is the first thing every tester sees, and
// it was the last page still laid out in absolute pixels — offsets authored on a 454 px AMOLED
// that overflowed a 240 px fenix 7S. Same measurement as the recording pages.
//
// The four GPS dots went in 0.8.2. They cost a row to say what the word beside them already
// said, and the row they freed went to the wind axis — the one setting that cannot be fixed
// after the session, because a turn detected without it is classified as a generic turn for
// good. The reminder therefore has to name the button that opens the menu, which makes it the
// longest string on the page and the one this test exists to measure.
(:test)
function startPageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = screenPx() / 2;
    var radius = RecordingView.fitRadius(dc, false, false);
    var titleFont = TEXT_FONTS[START_TITLE_FONT];
    var stateFont = TEXT_FONTS[START_STATE_FONT];
    var bodyFont = TEXT_FONTS[START_BODY_FONT];
    var hTitle = dc.getFontHeight(titleFont);
    var hState = dc.getFontHeight(stateFont);
    var hBody = dc.getFontHeight(bodyFont);
    var inkTitle = RecordingView.inkH(dc, titleFont);
    var inkState = RecordingView.inkH(dc, stateFont);
    var inkBody = RecordingView.inkH(dc, bodyFont);

    var yTitle = StartView.rowY(cy, hTitle, hState, hBody, 0);
    var yState = StartView.rowY(cy, hTitle, hState, hBody, 1);
    var yWind = StartView.rowY(cy, hTitle, hState, hBody, 2);
    var yHint = StartView.rowY(cy, hTitle, hState, hBody, 3);

    // rows in order, no overlap
    Test.assertMessage(yState - yTitle >= (hTitle + hState) / 2, "title/state overlap");
    Test.assertMessage(yWind - yState >= (hState + hBody) / 2, "state/wind overlap");
    Test.assertMessage(yHint - yWind >= hBody, "wind/hint overlap");

    // the block is centred: equal air above the title and below the hint
    Test.assertMessage((((cy - (yTitle - hTitle / 2)) - ((yHint + hBody / 2) - cy)).abs() <= 2),
        "start block off centre: " + (cy - (yTitle - hTitle / 2)).toString() + " vs "
            + ((yHint + hBody / 2) - cy).toString());
    // ...and it still leaves the screen breathing: this is a four-line page, not a data screen
    Test.assertMessage((yHint + hBody / 2) - (yTitle - hTitle / 2) <= screenPx() * 3 / 4,
        "the start block fills more than three quarters of the glass");

    // every row inside the glass, at the font the page will actually pick
    assertStartRow(dc, START_TITLE, yTitle, cy, radius, START_TITLE_FONT, inkTitle);
    // 0.9.2: the GPS state is the screen's answer and gets the title's rung, not the body's
    assertStartRow(dc, "GPS ready", yState, cy, radius, START_STATE_FONT, inkState);
    Test.assertMessage(dc.getFontHeight(stateFont) >= dc.getFontHeight(titleFont),
        "the app's name is still bigger than the answer to the screen's only question");
    assertStartRow(dc, START_HINT, yHint, cy, radius, START_BODY_FONT, inkBody);

    // The wind row in both its forms. The reminder is the longest string the page can hold,
    // so unlike the others it is allowed to STEP DOWN a rung rather than being required to
    // land at FONT_SMALL — but it must still be inside the glass and above the floor.
    // The third form is 0.9.0's: an axis the WATCH estimated carries a leading "~", one
    // character wider than the rider's own, which is exactly the sort of thing that overflows
    // the narrowest glass a release later.
    var winds = [START_WIND_UNSET, "wind 337° NNW", "wind ~337° NNW"];
    for (var i = 0; i < winds.size(); i++) {
        var f = RecordingView.fitFont(dc, TEXT_FONTS, START_BODY_FONT, winds[i],
            RecordingView.rowBudget(radius, yWind - cy, inkBody));
        var cr = cornerRadius(dc.getTextWidthInPixels(winds[i], f),
            RecordingView.inkH(dc, f), yWind, cy);
        Test.assertMessage(cr <= radius.toFloat(),
            "start wind '" + winds[i] + "' r=" + cr.format("%.0f") + " > " + radius.toString());
        logger.debug("wind row '" + winds[i] + "' at font height "
            + dc.getFontHeight(f).toString());
    }

    // the four GPS rungs are four distinct words, and the two that mean "not yet" are not
    // green — colour and word have to agree or the row says two things
    Test.assertEqual(StartView.gpsText(Position.QUALITY_NOT_AVAILABLE), "GPS ...");
    Test.assertEqual(StartView.gpsText(Position.QUALITY_POOR), "GPS weak");
    Test.assertEqual(StartView.gpsText(Position.QUALITY_USABLE), "GPS ready");
    Test.assertEqual(StartView.gpsText(Position.QUALITY_GOOD), "GPS good");
    Test.assertEqual(StartView.gpsColor(Position.QUALITY_USABLE), Graphics.COLOR_GREEN);
    Test.assertEqual(StartView.gpsColor(Position.QUALITY_GOOD), Graphics.COLOR_GREEN);
    Test.assertMessage(StartView.gpsColor(Position.QUALITY_POOR) != Graphics.COLOR_GREEN,
        "a weak fix must not read as ready");
    Test.assertMessage(
        StartView.gpsColor(Position.QUALITY_NOT_AVAILABLE) != Graphics.COLOR_GREEN,
        "no fix must not read as ready");

    // and the wind row says the axis when there is one, the way to set one when there is not
    var before = AppSettings.cfg.windManual;
    var wasSet = AppSettings.windEverSet;
    AppSettings.storeWindDirection(-1);
    Test.assertEqual(StartView.windText(), START_WIND_UNSET);
    AppSettings.storeWindDirection(22);
    Test.assertEqual(StartView.windText(), "wind 22° NNE");
    AppSettings.storeWindDirection(before);
    AppSettings.windEverSet = wasSet;

    logger.debug("start rows " + yTitle.toString() + "/" + yState.toString() + "/"
        + yWind.toString() + "/" + yHint.toString() + " on " + screenPx().toString()
        + "px, state font height " + hState.toString() + " over body " + hBody.toString());
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

// The foil DISTANCE share: the twin of foil %, and the right half of the Session page's band.
// What is asserted here is that it is a share of the ODOMETER and not of the clock, and that
// it says "--" rather than "0%" before there is a distance to take a share of.
(:test)
function foilDistanceShareIsAShareOfTheOdometer(logger as Test.Logger) as Boolean {
    var c = getApp().controller;
    var e = c.engine;
    var distWas = e.distM;
    var foilDistWas = e.detector.foilDistM;
    var foilTimeWas = e.detector.foilTimeS;
    var timerWas = e.timerS;

    e.distM = 0.0;
    e.detector.foilDistM = 0.0;
    Test.assertEqual(PageModel.value(PageModel.M_FOIL_DIST_PCT, c), "--");
    Test.assertMessage(e.foilDistPct() == 0.0, "no metres, no share");

    // Jan's 2026-08-24 session: 14.1 km of the 23.1 km covered on the foil, in 63:24 of the
    // 1:53:13 the timer ran. Two different denominators, two different numbers — which is
    // exactly why the band shows both.
    e.distM = 23100.0;
    e.detector.foilDistM = 14091.0;
    e.detector.foilTimeS = 3804.0;
    e.timerS = 6793.0;
    Test.assertEqual(PageModel.value(PageModel.M_FOIL_DIST_PCT, c), "61%");
    Test.assertEqual(PageModel.value(PageModel.M_FOIL_PCT, c), "56%");
    Test.assertEqual(PageModel.worstValue(PageModel.M_FOIL_DIST_PCT), "100%");
    // same family, same phase ink: it is the foil, seen the other way
    Test.assertEqual(PageModel.color(PageModel.M_FOIL_DIST_PCT, c), Ink.phaseFlying());
    Test.assertEqual(PageModel.glyph(PageModel.M_FOIL_DIST_PCT),
        PageModel.glyph(PageModel.M_FOIL_PCT));
    logger.debug("foil dist " + PageModel.value(PageModel.M_FOIL_DIST_PCT, c) + " vs time "
        + PageModel.value(PageModel.M_FOIL_PCT, c));

    e.distM = distWas;
    e.detector.foilDistM = foilDistWas;
    e.detector.foilTimeS = foilTimeWas;
    e.timerS = timerWas;
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

    // it is a property of the page, not of a cell: the shipped foil page has foil %
    PageModel.build({});
    Test.assertMessage(PageModel.pageHasMetric(1, PageModel.M_FOIL_PCT),
        "default foil page must carry the foil arc");
    Test.assertMessage(PageModel.pageDrawsFoilArc(1), "default foil page draws the arc");
    Test.assertMessage(!PageModel.pageDrawsFoilArc(0),
        "default main page has no foil % and so no arc");
    Test.assertMessage(!PageModel.pageDrawsFoilArc(2), "records page");
    // ...and LAYOUT_FOIL earns the arc by BEING the foil page, with every slot empty: it reads
    // no slot, so a rider who clears them must not lose the sweep the page is named after.
    PageModel.build({
        "pg1Layout" => PageModel.LAYOUT_FOIL,
        "pg1s1" => PageModel.M_NONE, "pg1s2" => PageModel.M_NONE,
        "pg1s3" => PageModel.M_NONE, "pg1s4" => PageModel.M_NONE,
        "pg1s5" => PageModel.M_NONE,
        "pg2Layout" => 0, "pg3Layout" => 0, "pg4Layout" => 0, "pg5Layout" => 0,
        "pg6Layout" => 0, "pg7Layout" => 0
    });
    Test.assertMessage(!PageModel.pageHasMetric(0, PageModel.M_FOIL_PCT), "no slot carries it");
    Test.assertMessage(PageModel.pageDrawsFoilArc(0), "a slotless foil page still draws it");
    PageModel.build({});
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
    // Seven pages since 0.8.2, on every product since 0.9.2: the seventh is the breadcrumb
    // map, which used to be turned off on anything without WatchUi.MapTrackView and is now
    // drawn by RecordingView like every other page, so there is nothing left to gate it on.
    var pages = 7;
    Test.assertMessage(PageModel.count() == pages,
        "expected " + pages.toString() + " default pages, got "
            + PageModel.count().toString());

    // Page 1 is the bespoke main screen since 0.8.0. Its GIANT is slot 1 and defaults to the
    // best 10 s (0.8.2): the rider reads the watch when he is not moving, so a live
    // speedometer shows him 4 km/h and tells him nothing about the run he just did. Slots 2-5
    // are unread — the rest of the page is the point of the screen.
    Test.assertEqual(PageModel.layoutAt(0), PageModel.LAYOUT_MAIN);
    Test.assertEqual(PageModel.slotAt(0, 0), PageModel.M_BEST_10S);
    for (var s = 1; s < PageModel.SLOTS; s++) {
        Test.assertEqual(PageModel.slotAt(0, s), PageModel.M_NONE);
    }
    // the giant's inline suffix: a unit AND a caption, because "24.3" alone is not a fact.
    // A metric whose label already IS its unit prints it once, not twice.
    Test.assertEqual(PageModel.unitOf(PageModel.M_BEST_10S), AppSettings.speedLabel());
    Test.assertEqual(PageModel.caption(PageModel.M_BEST_10S), "best 10s");
    Test.assertEqual(PageModel.caption(PageModel.M_SPEED), "");
    Test.assertEqual(PageModel.caption(PageModel.M_DISTANCE), "");
    Test.assertEqual(PageModel.unitOf(PageModel.M_FLIGHTS), "");
    Test.assertEqual(PageModel.caption(PageModel.M_FLIGHTS), "flights");

    // Page 2 is the bespoke FOIL table since 0.8.2 — it reads no slot. Its five slots are
    // nevertheless still the old Session grid's, on purpose: a rider who sets page 2 back to
    // "Grid" in Garmin Connect gets exactly the page he had, and pg2s1 = foil % is what keeps
    // the bezel arc on the page in either layout.
    Test.assertEqual(PageModel.layoutAt(1), PageModel.LAYOUT_FOIL);
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

    // Page 7 is the breadcrumb map, shipped ON at last: it has been in the app since 0.7 and
    // in nobody's page cycle, because a page you have to go and find in Garmin Connect is a
    // page that does not exist. It goes last because it is the least glanceable of the seven.
    Test.assertEqual(PageModel.layoutAt(6), PageModel.LAYOUT_MAP);
    Test.assertMessage(PageModel.mapPage, "the map page ships on, on every product");

    // wrapping is total: no index can escape the page set
    Test.assertEqual(PageModel.wrap(-1), pages - 1);
    Test.assertEqual(PageModel.wrap(pages), 0);
    logger.debug("defaults: " + pages.toString()
        + " pages, main/foil/records/turns/clock/timeline/map");
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
        "pg6Layout" => PageModel.LAYOUT_OFF, "pg7Layout" => PageModel.LAYOUT_OFF
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

    // a map-only page set is legal on every product now — the page is ours to draw
    PageModel.build({
        "pg1Layout" => PageModel.LAYOUT_MAP,
        "pg2Layout" => PageModel.LAYOUT_OFF, "pg3Layout" => PageModel.LAYOUT_OFF,
        "pg4Layout" => PageModel.LAYOUT_OFF, "pg5Layout" => PageModel.LAYOUT_OFF,
        "pg6Layout" => PageModel.LAYOUT_OFF, "pg7Layout" => PageModel.LAYOUT_OFF
    });
    Test.assertEqual(PageModel.layoutAt(0), PageModel.LAYOUT_MAP);
    Test.assertMessage(PageModel.mapPage, "map page flag set");

    // every page off must still leave one readable screen
    PageModel.build({
        "pg1Layout" => 0, "pg2Layout" => 0, "pg3Layout" => 0,
        "pg4Layout" => 0, "pg5Layout" => 0, "pg6Layout" => 0, "pg7Layout" => 0
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
// LAYOUT_MAP is IN the list since 0.9.2. It used to be the one layout that could not be here,
// because it was the firmware's own MapTrackView and there is no painting that into an
// offscreen Dc — which is also why the crash Jan kept hitting on it was invisible to this
// suite. The breadcrumb is drawn by RecordingView now, so the page is exercised like any other
// (populated, empty, paused and with the PB flash over it).
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
    // a breadcrumb for the map page: a long thin reach, the case that must not be stretched
    var tLat = new [16] as Array<Float>;
    var tLon = new [16] as Array<Float>;
    var tFly = new [16] as Array<Boolean>;
    for (var i = 0; i < 16; i++) {
        tLat[i] = 45.87 + i * 0.0002;
        tLon[i] = 10.87 + i * 0.0040;
        tFly[i] = i % 3 != 0;
    }
    e.trackLat = tLat;
    e.trackLon = tLon;
    e.trackFly = tFly;
    e.trackN = 16;

    var layouts = [PageModel.LAYOUT_MAIN, PageModel.LAYOUT_HERO, PageModel.LAYOUT_GRID4,
        PageModel.LAYOUT_CELLS2, PageModel.LAYOUT_RECORDS, PageModel.LAYOUT_TURNS,
        PageModel.LAYOUT_CLOCK, PageModel.LAYOUT_TIMELINE, PageModel.LAYOUT_FOIL,
        PageModel.LAYOUT_MAP];
    var view = new RecordingView();
    for (var i = 0; i < layouts.size(); i++) {
        // every slot filled with a timer: the widest thing the catalog can produce
        PageModel.build({
            "pg1Layout" => layouts[i],
            "pg1s1" => PageModel.M_TIMER, "pg1s2" => PageModel.M_LONGEST,
            "pg1s3" => PageModel.M_HR, "pg1s4" => PageModel.M_FOIL_TIME,
            "pg1s5" => PageModel.M_BEST_10S,
            "pg2Layout" => 0, "pg3Layout" => 0, "pg4Layout" => 0,
            "pg5Layout" => 0, "pg6Layout" => 0, "pg7Layout" => 0
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
        "pg6Layout" => 0, "pg7Layout" => 0});
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
            "pg4Layout" => 0, "pg5Layout" => 0, "pg6Layout" => 0,
            "pg7Layout" => 0});
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
    var before = AppSettings.cfg.windManual;

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
    // the numbers' band is their INK height since 0.9.2: two NUMBER_HOT line boxes and two
    // labels came to 93 % of the glass, a fifth of it leading, and the bottom number was
    // paying for that in chord
    var ink = RecordingView.inkH(dc, Graphics.FONT_NUMBER_HOT);
    var hHot = ink;
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);

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
    // 0.9.2: the clock's band is FONT_NUMBER_MILD (the rider asked for a bigger time of day)
    // and the giant's band is its INK height, which is where the 42 px came from.
    var hC = dc.getFontHeight(Graphics.FONT_NUMBER_MILD);
    var hN = RecordingView.inkH(dc, Graphics.FONT_NUMBER_MEDIUM);
    var hD = RecordingView.stripBandH(dc);
    var hO = dc.getFontHeight(Graphics.FONT_LARGE);
    var hK = dc.getFontHeight(Graphics.FONT_MEDIUM);

    // the ring-aware radius must actually be TIGHTER than the glass, or the fix is inert
    Test.assertMessage(radius < RecordingView.fitRadius(dc, false, false),
        "fitRadius ignores the state ring");

    // rows in order, no overlap, block centred
    var y0 = RecordingView.mainRowY(cy, hC, hN, hD, hO, hK, 0);
    var y1 = RecordingView.mainRowY(cy, hC, hN, hD, hO, hK, 1);
    var y2 = RecordingView.mainRowY(cy, hC, hN, hD, hO, hK, 2);
    var y3 = RecordingView.mainRowY(cy, hC, hN, hD, hO, hK, 3);
    var y4 = RecordingView.mainRowY(cy, hC, hN, hD, hO, hK, 4);
    Test.assertMessage(y1 - y0 >= (hC + hN) / 2, "main clock/giant overlap");
    Test.assertMessage(y2 - y1 >= (hN + hD) / 2, "main giant/strip overlap");
    Test.assertMessage(y3 - y2 >= (hD + hO) / 2, "main strip/outcomes overlap");
    Test.assertMessage(y4 - y3 >= (hO + hK) / 2, "main outcomes/streak overlap");
    Test.assertMessage((((cy - (y0 - hC / 2)) - ((y4 + hK / 2) - cy)).abs() <= 1),
        "main block off centre: " + (cy - (y0 - hC / 2)).toString() + " vs "
            + ((y4 + hK / 2) - cy).toString());

    // row 0 — the clock, and the PAUSED word that replaces it. Both must fit the same row.
    // The band is FONT_NUMBER_MILD since 0.9.2 and the row is fitted through the NUMBER ladder
    // with a fall-back into the text fonts, so the clock gets the digits and the WORD that
    // replaces it (which is wider, and has no glyphs in a number font) steps down as before.
    var inkC = RecordingView.inkH(dc, Graphics.FONT_NUMBER_MILD);
    var tops = ["23:59", PAUSED_TEXT];
    for (var i = 0; i < tops.size(); i++) {
        var f = RecordingView.fitGiant(dc, tops[i],
            3, RecordingView.rowBudget(radius, y0 - cy, inkC));
        var r = cornerRadius(dc.getTextWidthInPixels(tops[i], f),
            RecordingView.inkH(dc, f), y0, cy);
        Test.assertMessage(r <= limit,
            "main row0 '" + tops[i] + "' r=" + r.format("%.0f") + " > " + limit);
        Test.assertMessage(dc.getFontHeight(f) >= dc.getFontHeight(Graphics.FONT_SMALL),
            "main row0 '" + tops[i] + "' fell below FONT_SMALL");
        Test.assertMessage(RecordingView.inkH(dc, f) <= hC,
            "main row0 '" + tops[i] + "' is taller than the band it was stacked with");
    }
    // ...and the clock itself must reach the rung the row was widened for
    var clockF = RecordingView.fitGiant(dc, "23:59", 3,
        RecordingView.rowBudget(radius, y0 - cy, inkC));
    Test.assertMessage(dc.getFontHeight(clockF) >= dc.getFontHeight(Graphics.FONT_NUMBER_MILD),
        "the clock did not reach FONT_NUMBER_MILD: " + dc.getFontHeight(clockF).toString()
            + " in a " + RecordingView.rowBudget(radius, y0 - cy, inkC).toString() + "px row");
    Test.assertMessage(dc.getFontHeight(clockF) > dc.getFontHeight(Graphics.FONT_LARGE),
        "the clock is no larger than the FONT_LARGE it used to be");

    // row 1 — the giant, which is now a catalog SLOT (best 10 s by default) with its unit and
    // caption inline beside the digits. Every metric the slot can hold is measured, at its
    // worst-case value, with the suffix taken out of the budget first — that is the fitter's
    // own arithmetic, and the inline suffix is the part of it that is new.
    var narrowest = 9999;
    for (var m = 1; m <= PageModel.M_MAX; m++) {
        var v = PageModel.worstValue(m);
        var unit = m == PageModel.M_SPEED || m == PageModel.M_BEST_2S
            || m == PageModel.M_BEST_10S ? "km/h" : PageModel.unitOf(m);
        var cap = PageModel.caption(m);
        var sufW = RecordingView.giantSuffixWidth(dc, unit, cap);
        var budget = RecordingView.rowBudget(radius, y1 - cy,
            RecordingView.inkH(dc, Graphics.FONT_NUMBER_MEDIUM)) - sufW;
        var gf = RecordingView.fitGiant(dc, v, 2, budget);
        var w = dc.getTextWidthInPixels(v, gf) + sufW;
        if (budget < narrowest) { narrowest = budget; }
        var r = cornerRadius(w, RecordingView.inkH(dc, Graphics.FONT_NUMBER_MEDIUM), y1, cy);
        Test.assertMessage(r <= limit, "main giant m" + m.toString() + " r="
            + r.format("%.0f") + " > " + limit);
        // a giant that has fallen to a label font is not a giant
        Test.assertMessage(dc.getFontHeight(gf) >= dc.getFontHeight(Graphics.FONT_LARGE),
            "main giant m" + m.toString() + " fell to a label font");
        // the suffix must sit inside the giant's own band, not spill into the strip below it
        var sy = RecordingView.suffixLineY(dc, y1, gf, 1, 2);
        Test.assertMessage(sy + dc.getFontHeight(Graphics.FONT_XTINY) / 2 <= y1 + hN / 2,
            "main giant caption m" + m.toString() + " spills out of the giant's band");
        Test.assertMessage(RecordingView.suffixLineY(dc, y1, gf, 0, 2) < sy,
            "the unit line is not above the caption line");
    }
    // the DEFAULT giant must stay in the NUMBER ladder: it is the page's hero, and stepping
    // out of it would mean the inline suffix cost more than the unit row it replaced
    var defF = RecordingView.fitGiant(dc, "99.9", 2,
        RecordingView.rowBudget(radius, y1 - cy,
            RecordingView.inkH(dc, Graphics.FONT_NUMBER_MEDIUM))
        - RecordingView.giantSuffixWidth(dc, "km/h", "best 10s"));
    Test.assertMessage(dc.getFontHeight(defF) >= dc.getFontHeight(Graphics.FONT_NUMBER_MILD),
        "the default main giant fell out of the number ladder");

    // row 2 — the outcome strip, straddling the equator with the giant because it is the
    // widest thing on the page and that is where the chord is widest
    var stripW = RecordingView.rowBudget(radius, y2 - cy, hD);
    var shown = RecordingView.dotsShown(64, stripW);
    Test.assertMessage(shown >= 12, "the main strip holds only " + shown.toString() + " dots");
    var pitch = 2 * TL_DOT_R + TL_DOT_GAP;
    var rr = cornerRadius(shown * pitch - TL_DOT_GAP, 2 * TL_DOT_R, y2, cy);
    Test.assertMessage(rr <= limit, "main strip r=" + rr.format("%.0f") + " > " + limit);

    // row 3 — the outcome ladder at its worst case: three two-digit counts, no verdict.
    var tBudget = RecordingView.rowBudget(radius, y3 - cy,
        RecordingView.inkH(dc, Graphics.FONT_LARGE));
    var tf = RecordingView.tallyFont(dc, "99", "99", "99", "", tBudget, 0);
    var mask = RecordingView.tallyContent(dc, "99", "99", "99", "", tBudget, tf);
    Test.assertMessage(mask >= 0, "main outcome row cannot hold three counts");
    var sep = (mask & TALLY_SEPARATORS) != 0 ? TURNS_TALLY_SEP : TALLY_SEP_NARROW;
    rr = cornerRadius(RecordingView.tallyWidth(dc, "99", "99", "99", "", sep, tf),
        RecordingView.inkH(dc, tf), y3, cy);
    Test.assertMessage(rr <= limit, "main outcomes r=" + rr.format("%.0f") + " > " + limit);
    // the counts are rider-relevant numbers and must stay big — never a label font
    Test.assertMessage(dc.getFontHeight(tf) >= dc.getFontHeight(Graphics.FONT_SMALL),
        "main outcome counts fell below FONT_SMALL");

    // row 4 — the streak, at "dry 99 / 99"
    var sBudget = RecordingView.rowBudget(radius, y4 - cy,
        RecordingView.inkH(dc, Graphics.FONT_MEDIUM));
    var sf = RecordingView.streakFont(dc, "99", "99", sBudget, 1);
    rr = cornerRadius(RecordingView.streakWidth(dc, "99", "99", sf),
        RecordingView.inkH(dc, sf), y4, cy);
    Test.assertMessage(rr <= limit, "main streak r=" + rr.format("%.0f") + " > " + limit);
    Test.assertMessage(dc.getFontHeight(sf) >= dc.getFontHeight(Graphics.FONT_SMALL),
        "main streak fell below FONT_SMALL");
    // a one-digit streak must never be WIDER than the two-digit worst case
    Test.assertMessage(RecordingView.streakWidth(dc, "7", "12", sf)
        <= RecordingView.streakWidth(dc, "99", "99", sf), "streak worst case is not worst");
    logger.debug("main rows " + y0.toString() + "/" + y1.toString() + "/" + y2.toString()
        + "/" + y3.toString() + "/" + y4.toString() + " on r=" + radius.toString()
        + ", giant budget >= " + narrowest.toString() + "px, strip " + shown.toString()
        + " dots");
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
    var hN = RecordingView.inkH(dc, Graphics.FONT_NUMBER_THAI_HOT);   // the giant's band
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

    // Every HERO-shaped page's worst-case content, through the same fitters SummaryView draws
    // with. The arc flag matters: the Verdict page paints the foil arc, so it gets a tighter
    // radius. S4 (turns) is not in this list any more — it is the live Turns page verbatim
    // and is measured by turnsPageFitsRoundDisplay, which is the point of reusing it.
    //
    // S3's two rows swapped in 0.8.2: the LONGEST FLIGHT's duration and distance now sit
    // together, with the flight count below them. With the count between them the eye read
    // "7:04 · 31 · 2.2 km" as one series and the distance looked like the session's.
    var giants = ["100%", "99.9", "199:59", "99/99"];
    var arcs = [true, false, false, false];
    var units = ["on foil", "best 2s km/h", "longest flight", "takeoffs"];
    var rows1 = ["199:59 foil", "10s 99.9", "99.9 km longest", "99.9 to foil"];
    var rows2 = ["of 199:59", "99.9 km", "999 flights", "+199 bpm"];
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
    // The distance caption is a VALUE and moved from FONT_XTINY to FONT_SMALL in 0.8.2 — the
    // one place in the app where a number was drawn at a label's size. The taller line has to
    // clear the page-position dots on the bottom arc, which is what the box gave up 34 px of
    // margin to pay for. Assert both ends of that trade.
    var capY = SummaryView.trackCaptionY(dc);
    var capInk = RecordingView.inkH(dc, Graphics.FONT_SMALL);
    Test.assertMessage(capY - capInk / 2 >= cy + box / 2,
        "the track caption overlaps the track box");
    Test.assertMessage(capY + capInk / 2 < screenPx() - SummaryView.dotBand(dc)
        - SummaryView.dotRadius(dc),
        "the track caption (" + (capY + capInk / 2).toString() + ") reaches the page dots ("
            + (screenPx() - SummaryView.dotBand(dc) - SummaryView.dotRadius(dc)).toString()
            + ")");
    var rCap = cornerRadius(dc.getTextWidthInPixels("99.9 km", Graphics.FONT_SMALL), capInk,
        capY, cy);
    Test.assertMessage(rCap <= RecordingView.fitRadius(dc, false, false).toFloat(),
        "track caption corner " + rCap.format("%.0f") + " off the glass");
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
    // Six channels since 0.9.0: PB · flight · interval · takeoff · turn · auto wind.
    Test.assertEqual(AlertManager.CH_COUNT, 6);
    Test.assertMessage(AlertManager._lastMs.size() == AlertManager.CH_COUNT,
        "the timestamp array must have a slot per channel — a short one writes out of bounds "
        + "the first time the new channel fires, on the water and nowhere else");
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
    AlertManager.autoWindLocked();
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
    var before = AppSettings.cfg.windManual;
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

// ---- Auto wind: the acceptance against real sessions ----
//
// docs/testing.md layer 3, "recorded 1 Hz arrays extracted from fixtures by lab". The two
// `ciq` fixtures are replayed through `WingFoilCore.AutoWind` one sample at a time and the
// adopted direction is compared with the PHONE engine's answer for the same session
// (fixtures/goldens/<stem>.expected.json `wind.dirDeg`), which is the number the whole
// approximation is judged against.
//
// The band is +-20 deg, and it is not arbitrary. The adopted value may lag the converged
// estimate by up to HYSTERESIS_DEG (15) by construction — that is what the hysteresis IS —
// and the bin-resolution lobes and cones carry a few degrees more. 20 deg is under one
// 16-point compass step (22.5), i.e. the watch and the phone never disagree about what to
// print. Measured: -7.6 deg on 2026-08-07 and -4.0 deg on 2026-08-29.
//
// The arrays live in the DEVICE APP's tests, not the barrel's, so the data field's unit-test
// build does not carry ~14 kB it has no use for.

// One decoded sample from the AutoWindFixtures blob. `cell` undoes the generator's base-33
// alphabet, which steps over 34 and 92 — the quote and the backslash, the two codes a Monkey C
// string literal cannot hold raw. Deliberately NOT (:test)-annotated: the runner treats every
// annotated function as a test case and this one takes an argument and returns a Number.
function autoWindCell(c as Number) as Number {
    var v = c;
    if (v > 92) { v--; }
    if (v > 34) { v--; }
    return v - 33;
}

(:test)
function autoWindReplayFixtures(logger as Test.Logger) as Boolean {
    var dt = AutoWindFixtures.stepS();
    for (var f = 0; f < AutoWindFixtures.count(); f++) {
        var aw = new AutoWind();
        var chunks = AutoWindFixtures.chunksAt(f);
        var locked = -1;
        var maxStep = 0.0;
        var updates = 0;
        // Chunk by chunk, so the char array of a two-hour session is never resident whole:
        // the narrowest glass in the product list is also the tightest heap.
        for (var c = 0; c < chunks.size(); c++) {
            var chars = chunks[c].toCharArray();
            for (var i = 0; i + 2 < chars.size(); i += 3) {
                var cog = autoWindCell(chars[i].toNumber()) * 4.0 + 2.0;
                var speed = autoWindCell(chars[i + 1].toNumber()) * 0.2;
                var flying = chars[i + 2] == '1';
                var before = aw.dirDeg;
                var ev = aw.tick(dt, cog, speed, flying);
                if (ev == AutoWind.EV_LOCK) {
                    locked = aw.dirDeg;
                } else if (ev == AutoWind.EV_UPDATE) {
                    updates++;
                    var step = WingFoilCore.wrapDeg180(
                        (aw.dirDeg - before).toFloat()).abs();
                    if (step > maxStep) {
                        maxStep = step;
                    }
                }
            }
        }

        var name = AutoWindFixtures.nameAt(f);
        var engine = AutoWindFixtures.engineDegAt(f);
        Test.assertMessage(locked >= 0, name + ": the estimator never locked");
        var err = WingFoilCore.wrapDeg180(aw.dirDeg.toFloat() - engine);
        Test.assertMessage(err.abs() <= 20.0, name + ": watch says " + aw.dirDeg.toString()
            + " deg, engine says " + engine.format("%.2f") + " (" + err.format("%.1f")
            + " deg, band is +-20)");
        // "Never flips after lock" is the assertion that matters most: a flip would relabel
        // every tack as a jibe, and the one-shot backfill has already been spent by then.
        Test.assertMessage(maxStep <= 90.0, name + ": the axis flipped after locking, largest"
            + " adopted step " + maxStep.format("%.1f") + " deg");
        Test.assertMessage(aw.distanceM > 5000.0,
            name + ": only " + aw.distanceM.format("%.0f") + " m of flying reached the "
            + "histogram — the fixture or the gates are wrong");
        logger.debug(name + ": locked on " + locked.toString() + " deg, finished on "
            + aw.dirDeg.toString() + " (engine " + engine.format("%.2f") + ", "
            + err.format("%.1f") + "), " + updates.toString() + " update(s) over "
            + aw.distanceM.format("%.0f") + " m");
    }
    return true;
}

// ---- Auto wind: precedence and the "~" mark ----
//
// Manual ALWAYS wins. A bearing the rider entered is a statement of fact; the estimate is an
// inference from an hour of headings, and an inference must never overwrite a fact — least of
// all silently, mid-session, on a rider who set the axis precisely because he distrusted a
// guess. And an estimate the rider cannot tell from a measurement is worse than no estimate,
// so every place a bearing is shown marks it.
(:test)
function manualWindAlwaysBeatsTheEstimate(logger as Test.Logger) as Boolean {
    var before = AppSettings.cfg.windManual;
    var wasSet = AppSettings.windEverSet;
    var wasAuto = AppSettings.autoWindEverSet;

    AppSettings.storeWindDirection(-1);
    AppSettings.cfg.setAutoWind(-1);
    Test.assertEqual(AppSettings.cfg.windDirection, -1);
    Test.assertMessage(!AppSettings.cfg.windIsAuto(), "nothing set is not an estimate");
    Test.assertEqual(AppSettings.windLabel(), "--");

    // The watch works it out: the axis fills, and it is marked.
    AppSettings.applyAutoWind(200);
    Test.assertEqual(AppSettings.cfg.windDirection, 200);
    Test.assertMessage(AppSettings.cfg.windIsAuto(), "an unaccompanied estimate IS the axis");
    Test.assertEqual(AppSettings.windLabel(), "~SSW");
    Test.assertEqual(AppSettings.cfg.compassLabel(), "SSW");
    Test.assertMessage(AppSettings.autoWindEverSet, "the estimate arms the FIT counts");
    Test.assertMessage(FitFields.writesTurnCounts(),
        "an estimated axis classifies turns, so the counts are real and must be written");
    Test.assertMessage(StartView.windText().find("~") != null,
        "the start screen must mark an estimate: " + StartView.windText());

    // The rider disagrees. From here the estimate is not consulted at all.
    AppSettings.storeWindDirection(45);
    Test.assertEqual(AppSettings.cfg.windDirection, 45);
    Test.assertEqual(AppSettings.cfg.windAuto, 200);
    Test.assertMessage(!AppSettings.cfg.windIsAuto(), "manual must win");
    Test.assertEqual(AppSettings.windLabel(), "NE");
    Test.assertMessage(StartView.windText().find("~") == null,
        "a rider-set axis must NOT be marked: " + StartView.windText());

    // ...and a later estimate still does not displace it.
    AppSettings.applyAutoWind(310);
    Test.assertEqual(AppSettings.cfg.windDirection, 45);

    // Clearing the manual bearing hands the axis back to the estimate rather than to nothing.
    AppSettings.storeWindDirection(-1);
    Test.assertEqual(AppSettings.cfg.windDirection, 310);
    Test.assertMessage(AppSettings.cfg.windIsAuto(), "the estimate takes over again");

    AppSettings.cfg.setAutoWind(-1);
    AppSettings.storeWindDirection(before);
    AppSettings.windEverSet = wasSet;
    AppSettings.autoWindEverSet = wasAuto;
    logger.debug("precedence: manual > auto > unset, estimates marked \"~\"");
    return true;
}

// ---- Release bookkeeping ----
// The FIT's app_version high byte IS the app's minor version. They drifted once (the app was
// 0.7.0 while the byte still said 1) and nothing noticed, because nothing held them together.
(:test)
function appVersionAgreesWithTheFitByte(logger as Test.Logger) as Boolean {
    Test.assertEqual(FitSchema.APP_VERSION, "0.9.0");
    Test.assertEqual(FitSchema.APP_MINOR, 9);
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
    Test.assertEqual(FitSchema.APP_MINOR * 256 + FitSchema.SCHEMA_VERSION, 9 * 256 + 2);
    logger.debug("release " + FitSchema.APP_VERSION + ", app_version byte "
        + (FitSchema.APP_MINOR * 256 + FitSchema.SCHEMA_VERSION).toString());
    return true;
}

// ---- Paging ----
// It used to be a state machine. The map page was the firmware's MapTrackView, so paging onto
// it PUSHED a second view over RecordingView, paging off it popped, a settings reload could
// strand the pushed view, and while PAUSED the map was skipped entirely because a native view
// can carry no PAUSED banner. 0.9.2 draws the breadcrumb itself, so all of that is gone and
// what is left is index arithmetic — including onto the map, paused, which is the case the
// skip existed to prevent and which is now simply fine.
(:test)
function pagingIsPlainIndexArithmetic(logger as Test.Logger) as Boolean {
    // page 1 main, page 2 map, page 3 clock
    PageModel.build({
        "pg1Layout" => PageModel.LAYOUT_MAIN,
        "pg2Layout" => PageModel.LAYOUT_MAP,
        "pg3Layout" => PageModel.LAYOUT_CLOCK,
        "pg4Layout" => 0, "pg5Layout" => 0, "pg6Layout" => 0, "pg7Layout" => 0
    });
    Test.assertEqual(PageModel.count(), 3);
    Test.assertEqual(PageModel.layoutAt(1), PageModel.LAYOUT_MAP);

    // wrapping is total, in both directions
    Test.assertEqual(PageModel.wrap(0 + 1), 1);
    Test.assertEqual(PageModel.wrap(2 + 1), 0);
    Test.assertEqual(PageModel.wrap(0 - 1), 2);

    // a page set that is nothing but map pages is a page set like any other
    PageModel.build({
        "pg1Layout" => PageModel.LAYOUT_MAP,
        "pg2Layout" => PageModel.LAYOUT_MAP,
        "pg3Layout" => 0, "pg4Layout" => 0, "pg5Layout" => 0, "pg6Layout" => 0,
        "pg7Layout" => 0
    });
    Test.assertEqual(PageModel.count(), 2);
    Test.assertEqual(PageModel.layoutAt(0), PageModel.LAYOUT_MAP);
    Test.assertEqual(PageModel.wrap(1 + 1), 0);

    PageModel.build({});
    PageNav.index = 0;
    logger.debug("paging is wrap(index + dir); the map is an ordinary page in it");
    return true;
}

// ---- MAP page geometry ----
// The self-drawn breadcrumb: a square inscribed in the glass, the distance under it, and the
// "you are here" dot on the newest point. Same measurement the post-save Track page gets, on
// the page a rider is looking at while wet.
(:test)
function mapPageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = screenPx() / 2;
    var radius = RecordingView.fitRadius(dc, false, false);
    var limit = radius.toFloat();
    var box = RecordingView.mapBox(dc, radius);

    Test.assertMessage(box > 0 && box <= screenPx(), "map box " + box.toString()
        + " is not inside a " + screenPx().toString() + "px glass");
    // all four corners of the square, not just its edges — this is a round display
    var rBox = cornerRadius(box, box, cy, cy);
    Test.assertMessage(rBox <= limit + 1.0,
        "map box corners r=" + rBox.format("%.0f") + " > " + limit);

    // the distance caption hangs off the bottom of the box and is a VALUE, so FONT_SMALL is
    // its floor — it may not overlap the track and it may not run off the glass
    var capY = RecordingView.mapCaptionY(dc, box);
    var capInk = RecordingView.inkH(dc, Graphics.FONT_SMALL);
    Test.assertMessage(capY - capInk / 2 >= cy + box / 2 - 1,
        "the map caption overlaps the track box");
    var rCap = cornerRadius(dc.getTextWidthInPixels("99.9 km", Graphics.FONT_SMALL), capInk,
        capY, cy);
    Test.assertMessage(rCap <= limit,
        "map caption corner " + rCap.format("%.0f") + " > " + limit);

    // before the first fix the page says so, in a line that has to fit the middle of the glass
    var wf = RecordingView.fitFont(dc, TEXT_FONTS, 0, MAP_WAITING,
        RecordingView.rowBudget(radius, 0, RecordingView.inkH(dc, TEXT_FONTS[0])));
    var rWait = cornerRadius(dc.getTextWidthInPixels(MAP_WAITING, wf),
        RecordingView.inkH(dc, wf), cy, cy);
    Test.assertMessage(rWait <= limit,
        "'" + MAP_WAITING + "' corner " + rWait.format("%.0f") + " > " + limit);
    Test.assertMessage(dc.getFontHeight(wf) >= dc.getFontHeight(Graphics.FONT_SMALL),
        "the waiting line fell below FONT_SMALL");

    // the position marker is a dot, not a pixel
    Test.assertMessage(TrackDraw.markerRadius(dc) >= 3,
        "the position marker is " + TrackDraw.markerRadius(dc).toString() + "px");

    // aspect is preserved: a 15:1 reach draws as a band, and a single point does not divide
    // by zero. (The same two rules the post-save track keeps — one renderer, one set of them.)
    var wide = TrackDraw.scale(box, 0.030, 0.002);
    Test.assertMessage((0.030 * wide).toNumber() <= box + 1, "a wide track overflows its box");
    Test.assertMessage((0.002 * wide).toNumber() < box / 4,
        "a 15:1 track was stretched to fill the box");
    Test.assertMessage(TrackDraw.scale(box, 0.0, 0.0) <= 1.0e8, "degenerate track");
    // the summary's box is the same geometry with a different margin
    Test.assertEqual(SummaryView.trackBox(dc),
        TrackDraw.boxSide(screenPx() / 2 - SUM_TRACK_MARGIN));

    logger.debug("map box " + box.toString() + "px, caption at y " + capY.toString()
        + ", marker r" + TrackDraw.markerRadius(dc).toString());
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

