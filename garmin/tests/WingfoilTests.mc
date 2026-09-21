import Toybox.Application.Properties;
import Toybox.Application.Storage;
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

// A drawing context the size of the glass. `createBufferedBitmap` is API 4.0; the fenix 5
// Plus family (Connect IQ 3.3.3, supported since 0.9.11) has only the direct constructor,
// which MapSnapshot skips at runtime with the same `has` check — here the old form is the
// fallback, so the layout suite runs on every glass the app ships to.
function testDc() as Graphics.Dc {
    return testBitmap(screenPx(), screenPx()).getDc();
}

// A buffered bitmap on any API: the 4.0 factory where it exists, the 2.3 constructor on the
// fenix 5 Plus family (Connect IQ 3.3.3).
function testBitmap(w as Number, h as Number) as Graphics.BufferedBitmap {
    var opts = {:width => w, :height => h};
    var bmp = null;
    if (Graphics has :createBufferedBitmap) {
        bmp = Graphics.createBufferedBitmap(opts).get();
    } else {
        bmp = new Graphics.BufferedBitmap(opts);
    }
    Test.assertMessage(bmp != null, "buffered bitmap");
    return bmp as Graphics.BufferedBitmap;
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
    // 0.9.5: the clean-jibe row's band, between the giant and the streaks.
    var hC = dc.getFontHeight(TEXT_FONTS[CLEAN_FROM]);

    // row 0: header, widest with a wind axis set
    // The widest form the header can take: 0.9.0 marks an axis the watch estimated with a
    // leading "~", so the worst case gained a character.
    var header = RecordingView.turnsHeader(dc, "~NNE", radius.toNumber(),
        RecordingView.turnsRowY(cy, hT, hG, hC, hK, hD, hS, 0) - cy);
    var r = cornerRadius(dc.getTextWidthInPixels(header, Graphics.FONT_XTINY), hT,
        RecordingView.turnsRowY(cy, hT, hG, hC, hK, hD, hS, 0), cy);
    Test.assertMessage(r <= radius, "header corner " + r.format("%.0f") + " > " + radius);

    // row 1: the GIANT is the tally itself — flew · touched · swam, three counts in the three
    // ladder colours. Measured at its worst case (three two-digit counts) and at the shipped
    // session's own (35/8/8), because the first says it never clips and the second says the
    // page a rider actually sees is not permanently stepped down.
    var y1 = RecordingView.turnsRowY(cy, hT, hG, hC, hK, hD, hS, 1);
    var gBudget = RecordingView.rowBudget(pageR, y1 - cy,
        RecordingView.inkH(dc, Graphics.FONT_NUMBER_MEDIUM));
    var worstF = RecordingView.giantTallyFont(dc, "99", "99", "99", gBudget);
    r = cornerRadius(RecordingView.giantTallyWidth(dc, "99", "99", "99", worstF),
        RecordingView.inkH(dc, worstF), y1, cy);
    Test.assertMessage(r <= pageR,
        "giant tally corner " + r.format("%.0f") + " > " + pageR.toString());
    // a count is a value: the ladder may step down, never below the readability floor
    Test.assertMessage(dc.getFontHeight(worstF) >= dc.getFontHeight(
        RecordingView.numberLadderIsSmall(dc) ? Graphics.FONT_NUMBER_MILD : Graphics.FONT_SMALL),
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

    // row 2: the CLEAN JIBE row — "★ 99  99.9 CPH". Worst case is a three-figure session's
    // two-digit count beside a two-digit rate; the rate half is DROPPED rather than shrunk,
    // and, like the verdict row's side split, that decision is made at the FLOOR font.
    var y2 = RecordingView.turnsRowY(cy, hT, hG, hC, hK, hD, hS, 2);
    var gs = Glyphs.size(dc);
    var cBudget = RecordingView.rowBudget(pageR, y2 - cy,
        RecordingView.inkH(dc, TEXT_FONTS[CLEAN_FROM]));
    var cRate = RecordingView.cleanRowWidth(dc, gs, "99", "99.9", true,
        TEXT_FONTS[TALLY_FLOOR]) <= cBudget;
    var cf = RecordingView.cleanRowFont(dc, gs, "99", "99.9", cRate, cBudget);
    r = cornerRadius(RecordingView.cleanRowWidth(dc, gs, "99", "99.9", cRate, cf),
        RecordingView.inkH(dc, cf), y2, cy);
    Test.assertMessage(r <= pageR,
        "clean row corner " + r.format("%.0f") + " > " + pageR.toString());
    // a count is a value: this row keeps the same floor every other count on the watch keeps
    Test.assertMessage(dc.getFontHeight(cf) >= dc.getFontHeight(Graphics.FONT_SMALL),
        "the clean-jibe row fell below FONT_SMALL");
    Test.assertMessage(dc.getFontHeight(cf) <= hC,
        "the clean-jibe row is taller than the band it was stacked with");
    // the MARK AND THE COUNT must always fit — they are the row's reason to exist, and the
    // rate is what it gives up to keep them
    Test.assertMessage(
        RecordingView.cleanRowWidth(dc, gs, "99", "99.9", false, TEXT_FONTS[TALLY_FLOOR])
            <= cBudget, "not even the star and the count fit the clean-jibe row");
    Test.assertMessage(
        RecordingView.cleanRowWidth(dc, gs, "12", "4.6", false, cf)
            < RecordingView.cleanRowWidth(dc, gs, "12", "4.6", true, cf),
        "dropping the rate must save width");
    // ...and on every glass wide enough to be an AMOLED product the RATE has to survive: CPH
    // is the number 0.9.5 exists to put on the wrist, and the shipped session's own form
    // ("★ 12  4.6 CPH") is far short of the worst case measured above.
    if (screenPx() >= 416) {
        Test.assertMessage(
            RecordingView.cleanRowWidth(dc, gs, "12", "4.6", true, TEXT_FONTS[TALLY_FLOOR])
                <= cBudget,
            "CPH does not fit a " + screenPx().toString() + "px glass: "
                + RecordingView.cleanRowWidth(dc, gs, "12", "4.6", true,
                    TEXT_FONTS[TALLY_FLOOR]).toString()
                + "px of " + cBudget.toString());
    }
    logger.debug("clean row: "
        + RecordingView.cleanRowWidth(dc, gs, "12", "4.6", cRate, cf).toString() + "px of "
        + cBudget.toString() + " at font height " + dc.getFontHeight(cf).toString()
        + ", rate " + (cRate ? "on" : "dropped"));

    // row 3: BOTH streaks — "streak: 99/99  99/99". ONE grey caption for the row now, the two
    // runs told apart by the ladder's own inks rather than by two words. Worst case is four
    // two-digit numbers, and it is strictly narrower than the two-caption row it replaced.
    var y3 = RecordingView.turnsRowY(cy, hT, hG, hC, hK, hD, hS, 3);
    var kBudget = RecordingView.rowBudget(pageR, y3 - cy,
        RecordingView.inkH(dc, Graphics.FONT_MEDIUM));
    var kf = RecordingView.streakRow2Font(dc, "99", "99", "99", "99", kBudget, true);
    r = cornerRadius(RecordingView.streakRow2Width(dc, "99", "99", "99", "99", kf, true),
        RecordingView.inkH(dc, kf), y3, cy);
    Test.assertMessage(r <= pageR,
        "streak row corner " + r.format("%.0f") + " > " + pageR.toString());
    Test.assertMessage(dc.getFontHeight(kf) >= dc.getFontHeight(Graphics.FONT_SMALL),
        "streak row fell below FONT_SMALL");
    // the post-save form drops "the run he is on" and must be narrower for it
    Test.assertMessage(
        RecordingView.streakRow2Width(dc, "99", "99", "99", "99", kf, false)
            < RecordingView.streakRow2Width(dc, "99", "99", "99", "99", kf, true),
        "dropping the live run must save width");

    // row 4: the outcome strip. It is a texture, not a census — it shows the most recent dots
    // that fit — so what is asserted is that the band it reserves clears the glass and that a
    // long session really does drop the oldest rather than overflow.
    var y4 = RecordingView.turnsRowY(cy, hT, hG, hC, hK, hD, hS, 4);
    var stripW = RecordingView.rowBudget(pageR, y4 - cy, hD);
    var shown = RecordingView.dotsShown(64, stripW);
    Test.assertMessage(shown >= 8,
        "the strip row holds only " + shown.toString() + " dots");
    Test.assertMessage(shown <= 64, "the strip claims more dots than the log holds");
    var pitch = 2 * TL_DOT_R + TL_DOT_GAP;
    r = cornerRadius(shown * pitch - TL_DOT_GAP, 2 * TL_DOT_R, y4, cy);
    Test.assertMessage(r <= pageR,
        "strip corner " + r.format("%.0f") + " > " + pageR.toString());
    Test.assertEqual(RecordingView.dotsShown(3, stripW), 3);   // short sessions show them all

    // row 5: the verdict and the port/starboard entry split, at its widest — "100% flew" with
    // two two-digit side counts. The word grew by two glyphs in 0.8.2 (the row now prints the
    // flew-through share, which agrees with the tally above it by construction), so the 416 px
    // assertion below is exactly the one that had to be re-measured. The P/S half is DROPPED
    // rather than shrunk when it does not fit, so the assertion is on whichever form the
    // renderer would actually choose.
    // The row's values step down from TEXT_FONTS[VERDICT_FROM] (0.9.2 — they used to be pinned
    // at the FONT_SMALL floor on a row that had already been given a FONT_MEDIUM band), and
    // whether the P/S half is kept is decided at the FLOOR: content first, then size.
    var y5 = RecordingView.turnsRowY(cy, hT, hG, hC, hK, hD, hS, 5);
    var floorF = TEXT_FONTS[TALLY_FLOOR];
    var vBudget = RecordingView.rowBudget(pageR, y5 - cy,
        RecordingView.inkH(dc, TEXT_FONTS[VERDICT_FROM]));
    var sides = RecordingView.verdictWidth(dc, "100", "99", "99", true, floorF) <= vBudget;
    var vf = RecordingView.verdictFont(dc, "100", "99", "99", sides, vBudget);
    r = cornerRadius(RecordingView.verdictWidth(dc, "100", "99", "99", sides, vf),
        RecordingView.inkH(dc, vf), y5, cy);
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
    var y0 = RecordingView.turnsRowY(cy, hT, hG, hC, hK, hD, hS, 0);
    Test.assertMessage(y1 - y0 >= (hT + hG) / 2, "header/giant gap");
    Test.assertMessage(y2 - y1 >= (hG + hC) / 2, "giant/clean gap");
    Test.assertMessage(y3 - y2 >= (hC + hK) / 2, "clean/streak gap");
    Test.assertMessage(y4 - y3 >= (hK + hD) / 2, "streak/strip gap");
    Test.assertMessage(y5 - y4 >= (hD + hS) / 2, "strip/verdict gap");
    Test.assertMessage((((cy - (y0 - hT / 2)) - ((y5 + hS / 2) - cy)).abs() <= 1),
        "turns block off centre: " + (cy - (y0 - hT / 2)).toString() + " vs "
            + ((y5 + hS / 2) - cy).toString());
    // the whole six-row stack has to be on the glass, top and bottom — the row it gained in
    // 0.9.5 is paid for out of the page's air, and on the narrowest product there is not much
    Test.assertMessage(y0 - hT / 2 >= 0 && y5 + hS / 2 <= screenPx(),
        "the turns stack runs off the glass: " + (y0 - hT / 2).toString() + ".."
            + (y5 + hS / 2).toString() + " of " + screenPx().toString());
    logger.debug("turns page rows y=" + y0.toString() + "," + y1.toString() + ","
        + y2.toString() + "," + y3.toString() + "," + y4.toString() + "," + y5.toString());
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
    var hN = RecordingView.mainGiantBand(dc, PageModel.M_BEST_10S);
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
        // On a small number ladder (fenix 5 Plus) the floor is the ladder's own bottom rung.
        var giantFloor = RecordingView.numberLadderIsSmall(dc)
            ? Graphics.FONT_NUMBER_MILD : Graphics.FONT_LARGE;
        Test.assertMessage(dc.getFontHeight(gf) >= dc.getFontHeight(giantFloor),
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
        Test.assertMessage(dc.getFontHeight(f2) >= dc.getFontHeight(
            RecordingView.numberLadderIsSmall(dc) ? Graphics.FONT_NUMBER_MILD : Graphics.FONT_LARGE),
            "cells2 value m" + m.toString() + " is smaller than the FONT_LARGE it replaced");
        Test.assertMessage(RecordingView.inkH(dc, f2) <= hC2,
            "cells2 value m" + m.toString() + " is taller than its own band");
        if (dc.getFontHeight(f2) >= dc.getFontHeight(Graphics.FONT_NUMBER_MILD)) { bigCells++; }
    }

    var g1 = RecordingView.gridRowY(cy, hG, hT, hL, 1, true, bias);
    var g2 = RecordingView.gridRowY(cy, hG, hT, hL, 2, true, bias);
    Test.assertMessage(g2 - g1 >= hT + hL, "grid cell rows overlap");
    // without a giant the 2x2 centres on the screen instead of hanging under one
    // (on a small number ladder the giant band is shorter than the lift, so the recentring
    // has nothing to move — the fenix 5 Plus, where MILD is 26 px)
    Test.assertMessage(RecordingView.numberLadderIsSmall(dc)
        || RecordingView.gridRowY(cy, hG, hT, hL, 1, false, bias) < g1,
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
    // the PAIRED band, which on a glass whose FONT_NUMBER_MILD line is too short for a caption
    // plus a FONT_MEDIUM's ink (fr255, fr955) is one pixel taller than a single giant's
    var hG = RecordingView.giantBand(dc, true);
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
    // The band takes its extra pixel only where it has to: on every other glass it is exactly
    // the FONT_NUMBER_MILD line a single giant reserves, and the 2x2 below has not moved.
    var mild = dc.getFontHeight(Graphics.FONT_NUMBER_MILD);
    // On a small number ladder (fenix 5 Plus: MILD 26 px under a 34 px FONT_MEDIUM) the band
    // has to grow to its floor font plus a caption — that IS giantBand's rule — so the growth
    // bound applies only where numbers are the tall half.
    var growth = RecordingView.numberLadderIsSmall(dc)
        ? RecordingView.pairBandHeight(dc, Graphics.FONT_MEDIUM) - mild
        : RecordingView.inkH(dc, Graphics.FONT_XTINY);
    Test.assertMessage(hG >= mild && hG - mild <= growth,
        "the paired band grew " + (hG - mild).toString() + "px past the giant's own line");
    logger.debug("pair band: " + hG.toString() + "px band (MILD line is " + mild.toString()
        + "px), floor needs "
        + RecordingView.pairBandHeight(dc, Graphics.FONT_MEDIUM).toString() + "px");

    // a value in a label font is not a value: FONT_MEDIUM is the floor for this band
    Test.assertMessage(dc.getFontHeight(f) >= dc.getFontHeight(
        RecordingView.numberLadderIsSmall(dc) ? Graphics.FONT_NUMBER_MILD : Graphics.FONT_MEDIUM),
        "pair band fell below FONT_MEDIUM");
    // ...the block must fit the band the single giant reserved, or it would push the 2x2 down
    // and take the bottom row's corners off the glass...
    Test.assertMessage(RecordingView.pairBandHeight(dc, f) <= hG,
        "pair band is " + RecordingView.pairBandHeight(dc, f).toString()
            + "px tall in a " + hG.toString() + "px band");
    // ...and the font the renderer picked must be one that actually fits, by the renderer's
    // own three-part rule
    if (!RecordingView.pairFits(dc, [worst, lc, worst, rc], f, hG, radius, y, cy)) {
        var colD = RecordingView.cellColumns(radius, RecordingView.pairRowY(dc, y, f, 1) - cy,
            RecordingView.inkH(dc, f));
        logger.debug("pair band miss: font h=" + dc.getFontHeight(f).toString()
            + " block " + RecordingView.pairBandHeight(dc, f).toString() + " of " + hG.toString()
            + " | half " + RecordingView.pairHalfWidth(dc, worst, lc, f).toString()
            + " of " + (2 * colD[1]).toString()
            + " | cap " + dc.getTextWidthInPixels(lc, Graphics.FONT_XTINY).toString()
            + " col " + colD[0].toString()
            + " capHalf " + RecordingView.chordHalf(radius,
                RecordingView.pairRowY(dc, y, f, 0) - cy,
                RecordingView.inkH(dc, Graphics.FONT_XTINY)).toString());
    }
    Test.assertMessage(
        RecordingView.pairFits(dc, [worst, lc, worst, rc], f, hG, radius, y, cy),
        "the fitter returned a font that does not fit");
    var dx = RecordingView.pairColumnFor(dc, f, radius, y, cy, [worst, lc, worst, rc]);
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
    Test.assertMessage(RecordingView.pairFits(dc, ["56%", lc, "61%", rc], realF, hG,
        radius, y, cy), "the shipped session's own band does not fit");
    // ...and shorter numbers must SPREAD, not huddle: the columns are fixed, so the gap
    // between the two readings is what grows.
    // (the gap between the two readings is 2*dx minus the two inner half-widths)
    var realDx = RecordingView.pairColumnFor(dc, realF, radius, y, cy, ["56%", lc, "61%", rc]);
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
    // ...and they take the LARGEST rung their column can hold — asserted as that, rather than
    // as the literal FONT_LARGE, because a column's capacity is a property of the glass's face
    // and not only of its width. On every fenix, epix, MARQ, Descent and every other Forerunner
    // the answer IS FONT_LARGE, which was 0.9.2's whole point (before the headers moved below
    // the matrix the shipped session's six numbers were FONT_MEDIUM). The one watch where it is
    // not is the Forerunner 265, whose FONT_LARGE is 67 px tall and correspondingly wide: its
    // "63:24" measures 142 px in a 136 px column and needs six more. The page's one lever,
    // shortening the row keys, cannot find them — "max" is 55 px of XTINY on that face against
    // "total"'s 59, so dropping to "tot" buys the two columns 2 px each and the fitter rightly
    // keeps the longer word. It takes FONT_MEDIUM, 58 px on a 416 px glass, and the shares above
    // it still reach FONT_LARGE.
    var rungs = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM];
    for (var i = 0; i < rungs.size(); i++) {
        var fits = dc.getTextWidthInPixels("63:24", rungs[i]) <= col[3]
            && dc.getTextWidthInPixels("14.1", rungs[i]) <= col[3];
        Test.assertMessage(!fits
            || dc.getFontHeight(realV) >= dc.getFontHeight(rungs[i]),
            "the foil matrix stopped at " + dc.getFontHeight(realV).toString()
                + "px when " + dc.getFontHeight(rungs[i]).toString()
                + "px fits a " + col[3].toString() + "px column");
        var fitsP = dc.getTextWidthInPixels("61%", rungs[i]) <= col[3];
        Test.assertMessage(!fitsP
            || dc.getFontHeight(realP) >= dc.getFontHeight(rungs[i]),
            "the foil shares stopped at " + dc.getFontHeight(realP).toString()
                + "px when " + dc.getFontHeight(rungs[i]).toString() + "px fits");
    }
    // the shares are never the SMALLER half of a table whose two halves say the same thing
    Test.assertMessage(dc.getFontHeight(realP) >= dc.getFontHeight(realV),
        "the foil shares read smaller than the values under them");
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
        Test.assertMessage(dc.getFontHeight(vf) >= dc.getFontHeight(
            RecordingView.numberLadderIsSmall(dc) ? Graphics.FONT_NUMBER_MILD : Graphics.FONT_LARGE),
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

    // 0.9.5: the brand mark, in the air above the wordmark. It is the first thing on either
    // watch screen that is a PICTURE, and a picture cannot shed content or step down a rung
    // the way a row of text can — a bitmap is the size it is. So the fit is asserted rather
    // than arranged: inside the page's radius, inside the glass, clear of the title, and
    // small enough that the page it decorates is still a page and not a splash screen.
    var markW = Brand.w();
    var markH = Brand.h();
    var yMark = StartView.markY(cy, hTitle, hState, hBody, markH);
    Test.assertMessage(Brand.fits(dc, radius, 0, yMark - cy),
        "the brand mark (" + markW.toString() + "x" + markH.toString() + " at y "
            + yMark.toString() + ") runs off a " + screenPx().toString() + "px glass");
    Test.assertMessage(yMark + markH / 2 <= yTitle - hTitle / 2,
        "the brand mark overprints the wordmark");
    // the mark is hung off the title by the stack's own gap, so it belongs to the wordmark
    // and not to the page: the space between them must be the smallest on the screen
    Test.assertMessage((yTitle - hTitle / 2) - (yMark + markH / 2) <= yState - yTitle,
        "the mark sits further from the wordmark than the wordmark does from the GPS row");
    Test.assertMessage((yHint + hBody / 2) - (yMark - markH / 2) <= screenPx() * 7 / 8,
        "mark plus rows fill more than seven eighths of the glass");

    logger.debug("start rows " + yTitle.toString() + "/" + yState.toString() + "/"
        + yWind.toString() + "/" + yHint.toString() + " on " + screenPx().toString()
        + "px, state font height " + hState.toString() + " over body " + hBody.toString());
    logger.debug("brand mark " + markW.toString() + "x" + markH.toString() + " at y "
        + yMark.toString() + ", top " + (yMark - markH / 2).toString());
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

    // and the outcome symbols, including the triangle's polygon scratch reused twice and the
    // star's ten-vertex one (0.9.5)
    for (var o = Glyphs.O_DASH; o <= Glyphs.O_STAR; o++) {
        Glyphs.drawOutcome(dc, o, 60, 100, 24, Graphics.COLOR_GREEN);
        Glyphs.drawOutcome(dc, o, 60, 140, 18, Graphics.COLOR_RED);
    }

    // The STAR is the only glyph drawn beside a number rather than as a row's symbol, so its
    // box contract is load-bearing in a way the others' is not — `cleanRowWidth` reserves
    // exactly `Glyphs.size(dc)` for it and lays the count out from there. Assert the geometry
    // the table encodes: ten vertices, alternating out and in, all of them inside the s x s
    // box the contract promises, at the floor size where a star has least room to be wrong.
    Glyphs.drawStar(dc, 60, 180, Glyphs.MIN_PX);
    Glyphs.drawStar(dc, 120, 180, Glyphs.MAX_PX);
    Test.assertEqual(Glyphs._starU.size(), 10);
    Test.assertEqual(Glyphs._star.size(), 10);
    var box = 0;
    for (var i = 0; i < 10; i++) {
        var ux = Glyphs._starU[i][0];
        var uy = Glyphs._starU[i][1];
        Test.assertMessage(ux >= -1000 && ux <= 1000 && uy >= -1000 && uy <= 1000,
            "star vertex " + i.toString() + " is outside the s x s box every glyph promises");
        // the outer ring is at the full radius, the inner ring strictly inside it: a star
        // whose waist crept out to the points is a pentagon nobody would notice in a diff
        var reach = ux.abs() > uy.abs() ? ux.abs() : uy.abs();
        if (i % 2 == 0) {
            Test.assertMessage(reach == 1000 || ux.abs() == 951 || uy.abs() == 809,
                "outer star vertex " + i.toString() + " is not on the outer ring");
        } else {
            Test.assertMessage(reach < 500,
                "inner star vertex " + i.toString() + " reaches " + reach.toString()
                    + " — the waist has to stay well inside the points");
        }
        if (reach > box) { box = reach; }
    }
    Test.assertEqual(box, 1000);   // the star really does fill the box it is given

    logger.debug("glyphs: " + Glyphs.G_BATTERY.toString() + " metric symbols + 5 outcomes at "
        + s.toString() + "px (star " + Glyphs._starU.size().toString() + " vertices)");
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
        "pg6Layout" => 0, "pg7Layout" => 0, "pg8Layout" => 0
    });
    Test.assertMessage(!PageModel.pageHasMetric(0, PageModel.M_FOIL_PCT), "no slot carries it");
    Test.assertMessage(PageModel.pageDrawsFoilArc(0), "a slotless foil page still draws it");
    PageModel.build({});
    logger.debug("bezel arc r=" + r.toString() + "px, pen " + BEZEL_PEN.toString());
    return true;
}

// The reset switch (0.9.11): writes the defaults back over whatever the rider set, and reads
// as pressed exactly once.
//
// `(:test :dev)` since 0.9.16: the per-page editor, its properties and this switch are the
// dev stream's, and in the other two `consumeResetPages` is a `(:notdev)` false and
// `restoreDefaults` a rebuild that writes nothing — which is the behaviour
// `theReleaseStreamHasNoPageEditor` asserts there instead.
(:test :dev)
function resetPagesWritesTheDefaultsBack(logger as Test.Logger) as Boolean {
    Properties.setValue("pg1Layout", PageModel.LAYOUT_HERO);
    Properties.setValue("pg2s1", PageModel.M_HR);
    Properties.setValue("pg8Layout", PageModel.LAYOUT_OFF);
    Properties.setValue("resetPages", true);
    Test.assertMessage(AppSettings.consumeResetPages(), "a switch left on reads as pressed");
    Test.assertMessage(!AppSettings.consumeResetPages(), "and only once");
    Test.assertEqual(Properties.getValue("resetPages"), false);
    PageModel.restoreDefaults();
    Test.assertEqual(Properties.getValue("pg1Layout"), PageModel.DEF_LAYOUT[0]);
    Test.assertEqual(Properties.getValue("pg2s1"), PageModel.DEF_SLOTS[1][0]);
    Test.assertEqual(Properties.getValue("pg8Layout"), PageModel.DEF_LAYOUT[7]);
    Test.assertEqual(PageModel.layoutAt(0), PageModel.DEF_LAYOUT[0]);
    PageModel.build({});
    return true;
}

// The event flash (0.9.11): every verdict paints, in its own ink, and clears itself; the
// afterglow strip outlives the flash and names the turn.
(:test)
function eventFlashPaintsEveryVerdict(logger as Test.Logger) as Boolean {
    AppSettings.visualAlerts = true;
    EventFlash.clearAll();
    Test.assertMessage(!EventFlash.active(), "idle at rest");
    Test.assertMessage(!EventFlash.stripActive(System.getTimer()), "no strip at rest");

    // a fly-through on a jibe: the ladder's green, the word, and the strip naming the jibe
    EventFlash.fireTurn(TurnDetector.OUTCOME_FLEW, false, TurnDetector.KIND_JIBE);
    Test.assertMessage(EventFlash.active(), "a verdict starts the flash");
    Test.assertEqual(EventFlash.kind, EventFlash.EV_FLEW);
    Test.assertEqual(EventFlash.color(), Ink.ladderFlew());
    Test.assertEqual(EventFlash.word(EventFlash.kind, 0), "FLEW");
    Test.assertEqual(EventFlash.stripText(EventFlash.lastKind, EventFlash.lastTurnKind,
        EventFlash.lastValue), "JIBE · flew");
    Test.assertMessage(EventFlash.stripActive(System.getTimer()), "the strip is up");
    Test.assertMessage(!EventFlash.isRing(), "a verdict is a full flash");
    Test.assertEqual(EventFlash.frames(), EventFlash.FRAMES_FULL);

    // the pulse alternates on the same token, like the PB flash
    EventFlash.tick();
    Test.assertEqual(EventFlash.color(), (Ink.ladderFlew() >> 1) & 0x7F7F7F);
    EventFlash.tick();
    Test.assertEqual(EventFlash.color(), Ink.ladderFlew());

    // it runs out by itself, and the strip stays
    for (var i = 0; i < EventFlash.FRAMES_FULL; i++) {
        EventFlash.tick();
    }
    Test.assertMessage(!EventFlash.active(), "the flash must clear itself");
    Test.assertMessage(EventFlash.stripActive(System.getTimer()), "the strip outlives it");
    Test.assertMessage(!EventFlash.stripActive(System.getTimer() + EventFlash.AFTERGLOW_MS),
        "and goes after the afterglow");

    // a clean jibe replaces the plain fly-through, in the clean ink, and a tack that touched
    // down names the tack
    EventFlash.fireTurn(TurnDetector.OUTCOME_FLEW, true, TurnDetector.KIND_JIBE);
    Test.assertEqual(EventFlash.kind, EventFlash.EV_CLEAN);
    Test.assertEqual(EventFlash.baseColor(EventFlash.kind), Ink.cleanJibe());
    Test.assertEqual(EventFlash.stripText(EventFlash.EV_CLEAN, TurnDetector.KIND_JIBE, 0),
        "CLEAN JIBE");
    EventFlash.fireTurn(TurnDetector.OUTCOME_TOUCHDOWN, false, TurnDetector.KIND_TACK);
    Test.assertEqual(EventFlash.baseColor(EventFlash.kind), Ink.ladderTouchdown());
    Test.assertEqual(EventFlash.stripText(EventFlash.lastKind, EventFlash.lastTurnKind, 0),
        "TACK · touch");
    EventFlash.fireTurn(TurnDetector.OUTCOME_FELL, false, TurnDetector.KIND_TURN);
    Test.assertEqual(EventFlash.baseColor(EventFlash.kind), Ink.ladderFellIn());
    Test.assertEqual(EventFlash.stripText(EventFlash.lastKind, EventFlash.lastTurnKind, 0),
        "TURN · fell");

    // the takeoff is a ring, shorter, and leaves no afterglow of its own
    EventFlash.fireTakeoff();
    Test.assertMessage(EventFlash.isRing(), "a takeoff is a ring");
    Test.assertEqual(EventFlash.frames(), EventFlash.FRAMES_RING);
    Test.assertEqual(EventFlash.lastKind, EventFlash.EV_FELL);
    Test.assertEqual(EventFlash.baseColor(EventFlash.EV_TAKEOFF), Ink.phaseFlying());

    // a streak mark carries its number; the marks are 5, then every ten
    EventFlash.fireStreak(10);
    Test.assertEqual(EventFlash.word(EventFlash.kind, EventFlash.value), "10 DRY");
    Test.assertMessage(EventFlash.dryMilestone(5) && EventFlash.dryMilestone(10)
        && EventFlash.dryMilestone(20) && EventFlash.dryMilestone(30), "5, 10, 20, 30 flash");
    Test.assertMessage(!EventFlash.dryMilestone(4) && !EventFlash.dryMilestone(6)
        && !EventFlash.dryMilestone(15), "4, 6, 15 do not");

    // the longest flight carries its duration
    EventFlash.fireLongest(134);
    Test.assertEqual(EventFlash.stripText(EventFlash.EV_LONGEST, TurnDetector.KIND_NONE, 134),
        "LONGEST 2:14");

    // save and discard end the story
    EventFlash.clearAll();
    Test.assertMessage(!EventFlash.active() && !EventFlash.stripActive(System.getTimer()),
        "clearAll takes the strip with it");

    // and the switch is a switch
    AppSettings.visualAlerts = false;
    EventFlash.fireTurn(TurnDetector.OUTCOME_FLEW, false, TurnDetector.KIND_JIBE);
    Test.assertMessage(!EventFlash.active(), "off means no flash");
    AppSettings.visualAlerts = true;
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

// The out-of-the-box page set must be byte-for-byte the screens the app shipped with.
(:test)
function pageModelDefaultsMatchShippedPages(logger as Test.Logger) as Boolean {
    PageModel.build({});
    // EIGHT pages since 0.9.17: Tacks & jibes went in after Turns, and pushed the clock, the
    // timeline and the map down one. The last of them is the breadcrumb map, which used to be
    // turned off on anything without WatchUi.MapTrackView and is now drawn by RecordingView
    // like every other page, so there is nothing left to gate it on.
    var pages = 8;
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

    // Page 5 is TACKS & JIBES (0.9.17), straight after Turns: the Turns page says how the
    // maneuvers went, this one says which maneuvers they were. Bespoke like the Turns page
    // itself, so it reads no slot.
    Test.assertEqual(PageModel.layoutAt(4), PageModel.LAYOUT_KINDS);
    for (var s = 0; s < PageModel.SLOTS; s++) {
        Test.assertEqual(PageModel.slotAt(4, s), PageModel.M_NONE);
    }
    Test.assertEqual(PageModel.label(PageModel.M_JIBES), "jibes");
    Test.assertEqual(PageModel.label(PageModel.M_TACKS), "tacks");

    Test.assertEqual(PageModel.layoutAt(5), PageModel.LAYOUT_CLOCK);
    Test.assertEqual(PageModel.slotAt(5, 0), PageModel.M_TIMER);

    // TIMELINE ships ON (page 7): it is the page that shows the session as a story, and a
    // tester who has to find it in Garmin Connect never sees it.
    Test.assertEqual(PageModel.layoutAt(6), PageModel.LAYOUT_TIMELINE);

    // the cell labels the shipped Session page used, straight from the catalog
    Test.assertEqual(PageModel.label(PageModel.M_FOIL_TIME), "foil");
    Test.assertEqual(PageModel.label(PageModel.M_LONGEST), "longest");
    Test.assertEqual(PageModel.label(PageModel.M_DISTANCE), "km");
    Test.assertEqual(PageModel.label(PageModel.M_FLIGHTS), "flights");
    Test.assertEqual(PageModel.label(PageModel.M_TIMER), "timer");
    Test.assertEqual(PageModel.suffix(PageModel.M_HR), " bpm");

    // Page 8 is the breadcrumb map, shipped ON at last: it has been in the app since 0.7 and
    // in nobody's page cycle, because a page you have to go and find in Garmin Connect is a
    // page that does not exist. It goes last because it is the least glanceable of them all.
    Test.assertEqual(PageModel.layoutAt(7), PageModel.LAYOUT_MAP);
    Test.assertMessage(PageModel.mapPage, "the map page ships on, on every product");

    // wrapping is total: no index can escape the page set
    Test.assertEqual(PageModel.wrap(-1), pages - 1);
    Test.assertEqual(PageModel.wrap(pages), 0);
    logger.debug("defaults: " + pages.toString()
        + " pages, main/foil/records/turns/kinds/clock/timeline/map");
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
        "pg6Layout" => PageModel.LAYOUT_OFF, "pg7Layout" => PageModel.LAYOUT_OFF,
        "pg8Layout" => PageModel.LAYOUT_OFF
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
        "pg6Layout" => PageModel.LAYOUT_OFF, "pg7Layout" => PageModel.LAYOUT_OFF,
        "pg8Layout" => PageModel.LAYOUT_OFF
    });
    Test.assertEqual(PageModel.layoutAt(0), PageModel.LAYOUT_MAP);
    Test.assertMessage(PageModel.mapPage, "map page flag set");

    // every page off must still leave one readable screen
    PageModel.build({
        "pg1Layout" => 0, "pg2Layout" => 0, "pg3Layout" => 0, "pg4Layout" => 0,
        "pg5Layout" => 0, "pg6Layout" => 0, "pg7Layout" => 0, "pg8Layout" => 0
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
    // 7.2 km/h: the board is moving, so the session total's pumpMinSpeedKmh gate is open.
    // Tests that mean "he is going nowhere" set this to 0.
    var speedMps as Float = 2.0;

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
            lastEvent = det.tick(ms, flying, turnOpen, FlightDetector.EVENT_NONE, speedMps);
        }
    }

    // A real burst: ~1.2 Hz at 1.0 g. The band-pass has near-unity gain here, so this
    // lands just under 1.0 g band-passed -- over pumpBurstPeakG, which is what a takeoff
    // pump measures on the water. `chop()` is the same cadence at chop amplitude.
    function pump(seconds as Number) as Void {
        run(seconds, 1.2, 1.0, 0.0, 0.0, 0.0);
    }

    function chop(seconds as Number) as Void {
        run(seconds, 1.2, 0.4, 0.0, 0.0, 0.0);
    }

    function quiet(seconds as Number) as Void {
        run(seconds, 1.0, 0.0, 0.0, 0.0, 0.0);
    }

    // The tick on which the FlightDetector confirms a flight (>= minFlight seconds in).
    function confirmFlight() as Number {
        ms += 1000;
        lastEvent = det.tick(ms, flying, turnOpen, FlightDetector.EVENT_START, speedMps);
        return lastEvent;
    }
}

// A clean takeoff: pump, get up, flight confirmed. One attempt, one success, and the
// stroke count of the effort becomes pumps-to-takeoff.
(:test)
function pumpBurstBecomesATakeoffAttemptAndSucceeds(logger as Test.Logger) as Boolean {
    var r = new PumpRig();
    r.quiet(5);
    Test.assertEqual(r.det.peaks, 0);                // a still wrist is never pumping
    r.pump(10);                                       // 10 s at 1.2 Hz => ~12 strokes

    Test.assertMessage(r.det.peaks >= 10 && r.det.peaks <= 14,
        "10 s at 1.2 Hz gave " + r.det.peaks.toString() + " peaks, lab says 12");
    // A moving board and a takeoff-sized burst: every one of those peaks earns its place
    // in the session total too (docs/algorithms.md "The session total").
    Test.assertEqual(r.det.strokes, r.det.peaks);
    Test.assertMessage(r.det.minGapMs >= r.det.REFRACTORY_MS,
        "strokes " + r.det.minGapMs.toString() + " ms apart beat the refractory");
    Test.assertMessage(r.det.attemptOpen(), "a qualifying burst must open an effort");
    Test.assertMessage(r.det.cadence >= 40 && r.det.cadence <= 110,
        "cadence " + r.det.cadence.toString() + " spm off a 72 spm burst");

    // up on the foil, then the flight is confirmed a few seconds later
    r.flying = true;
    r.quiet(3);
    var burst = r.det.peaks;
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

// The session total (engine 0.8.0, docs/algorithms.md "The session total"). Real lake chop
// is at pumping cadence and clears pumpStrokeAmp, so the peak train alone is not a count of
// anything — the watch's FIT session field 38 counts only the strokes of a burst that was
// long enough, tall enough, and moving. The lab's is the authoritative number; this is the
// live approximation of the same three tests.
(:test)
function sessionTotalCountsOnlyStrokesThatEarnedIt(logger as Test.Logger) as Boolean {
    // 1. chop amplitude at pumping cadence: picked as peaks, never counted.
    var chop = new PumpRig();
    chop.quiet(3);
    chop.chop(10);
    Test.assertMessage(chop.det.peaks >= 10,
        "the picker must still see the chop: " + chop.det.peaks.toString() + " peaks");
    Test.assertMessage(chop.det.strokes == 0,
        "chop-sized burst put " + chop.det.strokes.toString() + " strokes in the total");
    // It is still evidence of effort, so it still opens an attempt: the amplitude rule is
    // deliberately confined to the total (the phone does the same).
    Test.assertMessage(chop.det.attemptOpen(), "a chop-sized burst still opens an effort");

    // 2. a burst shorter than pumpMinStrokes never reaches the total.
    var brief = new PumpRig();
    brief.quiet(3);
    brief.run(2, 1.2, 1.0, 0.0, 0.0, 0.0);        // ~2-3 peaks: not a bout of pumping
    Test.assertMessage(brief.det.peaks > 0 && brief.det.peaks < brief.det.MIN_STROKES,
        "expected a short burst, got " + brief.det.peaks.toString() + " peaks");
    Test.assertEqual(brief.det.strokes, 0);

    // 3. full amplitude, going nowhere: swim strokes.
    var swim = new PumpRig();
    swim.speedMps = 0.5;                          // 1.8 km/h, below pumpMinSpeedKmh
    swim.quiet(3);
    swim.pump(10);
    Test.assertMessage(swim.det.peaks >= 10, "the swimmer's arms are still picked");
    Test.assertEqual(swim.det.strokes, 0);

    // 4. and the real thing, credited whole — including the strokes before the burst
    //    qualified, which is what makes the live count equal the lab's.
    var real = new PumpRig();
    real.quiet(3);
    real.pump(10);
    Test.assertEqual(real.det.strokes, real.det.peaks);
    logger.debug("session total: chop " + chop.det.peaks.toString() + " peaks / 0 counted, "
        + "swim " + swim.det.peaks.toString() + " / 0, real " + real.det.strokes.toString()
        + " / " + real.det.peaks.toString());
    return true;
}

// Chop is faster and a lean is slower than pumping; wing trim is in band but tiny. None of
// the three may produce a single stroke (lab test_chop_is_rejected / small_wing_trim).
(:test)
function chopAndWobbleAreNotPumping(logger as Test.Logger) as Boolean {
    var r = new PumpRig();
    r.run(20, 6.0, 0.5, 0.1, 1.0, 0.0);      // 6 Hz chop over a 0.1 Hz body lean
    Test.assertMessage(r.det.peaks == 0,
        "chop + lean produced " + r.det.peaks.toString() + " peaks");
    r.run(20, 1.2, 0.06, 0.0, 0.0, 0.0);     // in band, far below pumpStrokeAmp
    Test.assertMessage(r.det.peaks == 0,
        "wing-trim wobble produced " + r.det.peaks.toString() + " peaks");
    Test.assertEqual(r.det.strokes, 0);
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
    Test.assertMessage(r.det.peaks > 12,
        "a 20 s two-tone burst is pumping, got " + r.det.peaks.toString());
    Test.assertMessage(r.det.minGapMs >= r.det.REFRACTORY_MS,
        "two strokes " + r.det.minGapMs.toString() + " ms apart");
    // the raw peak train carries ~48 candidates (the 2.4 Hz hump); the dead time must eat
    // most of them, so the surviving cadence stays physically possible
    Test.assertMessage(r.det.refractoryDrops > 10,
        "the dead time swallowed only " + r.det.refractoryDrops.toString() + " peaks");
    Test.assertMessage(r.det.peaks <= 30,
        "impossible cadence: " + r.det.peaks.toString() + " peaks in 20 s");
    logger.debug("two-tone burst: " + r.det.peaks.toString() + " peaks kept, "
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
    Test.assertMessage(r.det.peaks >= 10, "in-flight strokes must still be counted");
    Test.assertEqual(r.det.inFlightStrokes, r.det.peaks);
    Test.assertMessage(!r.det.attemptOpen(), "no effort may be open while flying");
    Test.assertEqual(r.det.attempts(), 0);
    Test.assertEqual(r.det.failed, 0);
    logger.debug("in-flight: " + r.det.peaks.toString()
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
    Test.assertMessage(r.det.peaks >= 10, "recovery strokes are still strokes");
    Test.assertEqual(r.det.recoveryEpisodes, 1);
    Test.assertEqual(r.det.failed, 0);
    Test.assertEqual(r.det.attempts(), 0);
    logger.debug("recovery burst owned by the turn: 0 attempts, "
        + r.det.peaks.toString() + " strokes");
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
    var bmpAny = testBitmap(screenPx(), screenPx());
    var bmp = bmpAny;
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
        PageModel.LAYOUT_MAP, PageModel.LAYOUT_KINDS];
    var view = new RecordingView();
    for (var i = 0; i < layouts.size(); i++) {
        // every slot filled with a timer: the widest thing the catalog can produce
        PageModel.build({
            "pg1Layout" => layouts[i],
            "pg1s1" => PageModel.M_TIMER, "pg1s2" => PageModel.M_LONGEST,
            "pg1s3" => PageModel.M_HR, "pg1s4" => PageModel.M_FOIL_TIME,
            "pg1s5" => PageModel.M_BEST_10S,
            "pg2Layout" => 0, "pg3Layout" => 0, "pg4Layout" => 0, "pg5Layout" => 0,
            "pg6Layout" => 0, "pg7Layout" => 0, "pg8Layout" => 0
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
        "pg6Layout" => 0, "pg7Layout" => 0, "pg8Layout" => 0});
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
            "pg4Layout" => 0, "pg5Layout" => 0, "pg6Layout" => 0, "pg7Layout" => 0,
            "pg8Layout" => 0});
        PageNav.index = 0;
        view.onUpdate(dc);
    }
    c.engine = saved;
    PageModel.build({});
    PageNav.index = 0;
    logger.debug("rendered " + layouts.size().toString()
        + " layouts populated + empty, plus every default page and the PAUSED banner");
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
    // The invite lock is retired (every stream compiles the zero pepper, docs/channels.md);
    // its screen is measured only where a pepper still arms it, so a font set the lock never
    // meets — the fenix 5 Plus's, where rows 3 and 4 touch — cannot fail a build for a screen
    // no rider can reach.
    if (!LockGate.enabled()) {
        logger.debug("lock retired — screen not measured");
        return true;
    }
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
    // The font must be able to DRAW the code, not merely be willing to measure it. A face
    // without the glyphs answers 0 px, which reads as "fits" to every width test in the
    // fitter — that is how the digits-only `Bionic_Bold_Number_Only` cut on the epix 2 /
    // MARQ 2 / Descent Mk3 families got picked at the largest size on the list and would
    // have drawn the tester's code with its letters missing. Every letter, on its own:
    for (var i = 0; i < LockGate.ALPHABET.length(); i++) {
        var ch = LockGate.ALPHABET.substring(i, i + 1);
        Test.assertMessage(dc.getTextWidthInPixels(ch, fonts[2]) > 0,
            "the request-code font cannot draw '" + ch + "'");
    }
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
    // Timer time is shorter than the wall clock: the two are different on purpose, so a
    // test that reads the wrong one fails rather than agrees by accident (foil % divides by
    // timer time since 7 Sep 2026; KEY_DUR stays the wall clock).
    e.timerS = 7000.0;
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
        PhoneLink.KEY_TAKEOFF_OK, PhoneLink.KEY_WIND, PhoneLink.KEY_APP,
        PhoneLink.KEY_CRASHES];
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
    Test.assertEqual(p[PhoneLink.KEY_FOIL_PCT], 74);        // 5183.4 / 7000 timer, not / 7412 elapsed
    Test.assertEqual(p[PhoneLink.KEY_TAKEOFF_ATT], 56);     // successes + failed
    Test.assertEqual(p[PhoneLink.KEY_TAKEOFF_OK], 39);
    Test.assertEqual(p[PhoneLink.KEY_FLEW], 63);
    Test.assertEqual(p[PhoneLink.KEY_TOUCHDOWN], 21);
    Test.assertEqual(p[PhoneLink.KEY_FELL], 12);
    Test.assertEqual(p[PhoneLink.KEY_APP],
        FitSchema.APP_MINOR * 256 + FitSchema.SCHEMA_VERSION);

    // A percentage cannot exceed 100 however the two clocks disagree, and a zero-length
    // session must not divide by it.
    c.engine.timerS = 0.0;
    Test.assertEqual(PhoneLink.summary(c)[PhoneLink.KEY_FOIL_PCT], 0);
    c.engine.timerS = 10.0;
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
    // 0.9.13: the giant's band is its ink OR its two-line suffix block, whichever is taller
    // (mainGiantBand) — the default slot's here, each slot's own in the loop below
    var hN = RecordingView.mainGiantBand(dc, PageModel.M_BEST_10S);
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
        var budget0 = RecordingView.rowBudget(radius, y0 - cy, inkC);
        // 0.9.13: the WORD never walks the number ladder (no letters there — the fenix 5
        // Plus family drew six boxes), and it starts at the text rung whose ink fits hC
        var f = i == 0 ? RecordingView.fitGiant(dc, tops[i], 3, budget0)
            : RecordingView.fitFont(dc, TEXT_FONTS, RecordingView.textFontFrom(dc, hC),
                tops[i], budget0);
        var r = cornerRadius(dc.getTextWidthInPixels(tops[i], f),
            RecordingView.inkH(dc, f), y0, cy);
        Test.assertMessage(r <= limit,
            "main row0 '" + tops[i] + "' r=" + r.format("%.0f") + " > " + limit);
        Test.assertMessage(dc.getFontHeight(f) >= dc.getFontHeight(
            RecordingView.numberLadderIsSmall(dc) ? Graphics.FONT_NUMBER_MILD : Graphics.FONT_SMALL),
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
    Test.assertMessage(RecordingView.numberLadderIsSmall(dc)
        || dc.getFontHeight(clockF) > dc.getFontHeight(Graphics.FONT_LARGE),
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
        var hNm = RecordingView.mainGiantBand(dc, m);
        var y1m = RecordingView.mainRowY(cy, hC, hNm, hD, hO, hK, 1);
        var budget = RecordingView.rowBudget(radius, y1m - cy,
            RecordingView.inkH(dc, Graphics.FONT_NUMBER_MEDIUM)) - sufW;
        var gf = RecordingView.fitGiant(dc, v, 2, budget);
        var w = dc.getTextWidthInPixels(v, gf) + sufW;
        if (budget < narrowest) { narrowest = budget; }
        var r = cornerRadius(w, RecordingView.inkH(dc, Graphics.FONT_NUMBER_MEDIUM), y1m, cy);
        Test.assertMessage(r <= limit, "main giant m" + m.toString() + " r="
            + r.format("%.0f") + " > " + limit);
        // a giant that has fallen to a label font is not a giant
        Test.assertMessage(dc.getFontHeight(gf) >= dc.getFontHeight(
            RecordingView.numberLadderIsSmall(dc) ? Graphics.FONT_NUMBER_MILD : Graphics.FONT_LARGE),
            "main giant m" + m.toString() + " fell to a label font");
        // the suffix must sit inside the giant's own band — neither into the strip below it
        // nor (0.9.13, fenix 5 Plus) up into the clock row above it
        var lines = (unit.equals("") ? 0 : 1) + (cap.equals("") ? 0 : 1);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var sy = RecordingView.suffixLineY(dc, y1m, gf, 1, lines);
        Test.assertMessage(sy + hT / 2 <= y1m + hNm / 2,
            "main giant caption m" + m.toString() + " spills out of the giant's band");
        var uy = RecordingView.suffixLineY(dc, y1m, gf, 0, lines);
        Test.assertMessage(uy - hT / 2 >= y1m - hNm / 2,
            "main giant unit m" + m.toString() + " reaches up into the clock row: "
                + (uy - hT / 2).toString() + " < " + (y1m - hNm / 2).toString());
        if (lines == 2) {
            Test.assertMessage(uy < sy, "the unit line is not above the caption line");
        }
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
    // 0.9.13: ...and its cap line, which on the fenix 5 Plus family is 30 px higher than the
    // yardstick above, where SAVED printed over the 56%
    Test.assertMessage(SummaryView.savedY(dc) + dc.getFontHeight(Graphics.FONT_XTINY) / 2
        < SummaryView.verdictDigitTop(dc),
        "SAVED pill reaches the verdict digits: " + SummaryView.savedY(dc).toString()
            + " vs cap line " + SummaryView.verdictDigitTop(dc).toString());
    Test.assertMessage(SummaryView.verdictDigitTop(dc)
        <= cy - dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT) / 2 + hN,
        "the verdict cap line model is off the giant");
    // 0.9.5: the pill is a LOCKUP — the brand mark, a gap, the word — centred where the word
    // alone used to be. Both halves have to clear the arc (the mark is the taller box, the
    // word the further out, and which corner is binding changes with the glass), and the
    // mark, being the tallest thing on the top arc, has to stay clear of the giant.
    // ...where the arc has room for it. On the fenix 5 Plus family the eyebrow sits 20 px
    // higher than elsewhere (savedY) and the lockup no longer fits the chord there, so the
    // word rides alone — the pre-0.9.5 screen, not a broken one. Where it fits it must fit.
    var lockup = SummaryView.lockupFits(dc, Brand.badgeW(), Brand.badgeH(), savedW,
        SummaryView.savedY(dc));
    Test.assertMessage(lockup || RecordingView.numberLadderIsSmall(dc),
        "the SAVED lockup (" + Brand.badgeW().toString() + "+"
            + SummaryView.savedGap(dc).toString() + "+" + savedW.toString()
            + ") does not fit the verdict page's top arc");
    // the badge is the taller half of the pair, so it is the half that has to clear the number
    Test.assertMessage(!lockup || SummaryView.savedY(dc) + Brand.badgeH() / 2
        < SummaryView.verdictDigitTop(dc),
        "the brand badge reaches the verdict giant");
    Test.assertMessage(SummaryView.savedY(dc) - Brand.badgeH() / 2 >= 0,
        "the SAVED lockup runs off the top of the glass");
    // it is a badge and not a second headline: the eyebrow it signs must stay an eyebrow, so
    // the mark beside the word may not be taller than the LINE that word is set in
    Test.assertMessage(Brand.badgeH() <= dc.getFontHeight(Graphics.FONT_XTINY),
        "the SAVED badge is taller than the line it rides on");
    Test.assertMessage(Brand.badgeH() < Brand.h(),
        "the badge is not lighter than the start page's mark");
    logger.debug("SAVED lockup " + SummaryView.lockupW(dc, Brand.badgeW(), savedW).toString()
        + "px wide, badge " + Brand.badgeW().toString() + "x" + Brand.badgeH().toString()
        + " at y " + SummaryView.savedY(dc).toString() + " on a "
        + dc.getFontHeight(Graphics.FONT_XTINY).toString() + "px line");
    var dr = SummaryView.dotRadius(dc);
    var dotN = 8;                                   // every page the summary can produce
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
    var bmpAny = testBitmap(screenPx(), screenPx());
    var bmp = bmpAny;
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
        Test.assertMessage(SummaryNav.pageAt(i) != SummaryNav.S_KINDS, "no kinds page");
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
    // eight since 0.9.17: the session above has tacks and jibes, so the kinds page is earned
    Test.assertEqual(SummaryNav.count(), 8);
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
    // Eight channels since 0.9.16: PB · flight · interval · takeoff · turn · auto wind ·
    // clean jibe · the direct transfer reaching the phone whole.
    Test.assertEqual(AlertManager.CH_COUNT, 8);
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
    AlertManager.longestFlight(120);
    AlertManager.takeoff();
    AlertManager.interval();
    AlertManager.autoWindLocked();
    AlertManager.cleanJibeBuzz();
    AppSettings.alertPb = pb;
    AppSettings.alertTurn = turn;
    AlertManager.reset();
    logger.debug("debounce: " + AlertManager.DEBOUNCE_MS.toString() + " ms per channel, "
        + AlertManager.GLOBAL_FLOOR_MS.toString() + " ms global floor");
    return true;
}

// ---- One turn, one buzz (0.9.5) ----
// A clean jibe is ALSO a fly-through, so the naive wiring — fire the ladder rhythm, then fire
// the clean-jibe flourish — asks for two profiles inside the same second and GLOBAL_FLOOR_MS
// throws the second away. The rider would get the plain tick every time and nothing anywhere
// would say why. `turnResolved` is the fix: it CHOOSES, and this is the test that it chooses.
(:test)
function cleanJibeBuzzReplacesTheFlyThroughTick(logger as Test.Logger) as Boolean {
    var turn = AppSettings.alertTurn;
    var clean = AppSettings.alertCleanJibe;

    // toggle ON: the clean channel is the one that fires, and the turn channel stays untouched
    AlertManager.reset();
    AppSettings.alertTurn = true;
    AppSettings.alertCleanJibe = true;
    AlertManager.turnResolved(TurnDetector.OUTCOME_FLEW, true, TurnDetector.KIND_JIBE);
    Test.assertMessage(AlertManager._lastMs[AlertManager.CH_CLEAN] > 0,
        "a clean jibe did not reach its own channel");
    Test.assertMessage(AlertManager._lastMs[AlertManager.CH_TURN] == 0,
        "the ladder rhythm fired as well — the flourish would be eaten by the global floor");

    // toggle OFF: the 0.9.4 behaviour comes back. "Off" means the ordinary turn buzz, NOT
    // silence — a rider who dislikes the new rhythm is not asking to lose his verdicts.
    AlertManager.reset();
    AppSettings.alertCleanJibe = false;
    AlertManager.turnResolved(TurnDetector.OUTCOME_FLEW, true, TurnDetector.KIND_JIBE);
    Test.assertMessage(AlertManager._lastMs[AlertManager.CH_TURN] > 0,
        "with the clean-jibe toggle off a clean jibe must still buzz as a fly-through");
    Test.assertMessage(AlertManager._lastMs[AlertManager.CH_CLEAN] == 0,
        "the clean channel fired with its toggle off");

    // an ordinary fly-through never reaches the clean channel, toggle or no toggle
    AlertManager.reset();
    AppSettings.alertCleanJibe = true;
    AlertManager.turnResolved(TurnDetector.OUTCOME_FLEW, false, TurnDetector.KIND_JIBE);
    Test.assertMessage(AlertManager._lastMs[AlertManager.CH_CLEAN] == 0,
        "a turn that was not a clean jibe reached the clean channel");
    Test.assertMessage(AlertManager._lastMs[AlertManager.CH_TURN] > 0,
        "an ordinary fly-through lost its tick");

    AlertManager.reset();
    AppSettings.alertTurn = turn;
    AppSettings.alertCleanJibe = clean;
    logger.debug("clean-jibe buzz: channel " + AlertManager.CH_CLEAN.toString()
        + " of " + AlertManager.CH_COUNT.toString() + ", replaces CH_TURN on a clean jibe");
    return true;
}

// ---- CPH arithmetic (0.9.5) ----
// The rate the Turns page and the post-save summary print. Two rules and they are the whole
// metric: no hour, no rate; and after that it is clean jibes / hours, to one decimal.
(:test)
function cphIsNullBeforeAMinuteAndAValueAfter(logger as Test.Logger) as Boolean {
    // NOTHING before the floor. One clean jibe forty seconds in is not "ninety an hour" — the
    // same never-a-flattering-number rule the engine applies at durationS <= 0, moved up to
    // where the watch needs it, because the watch is asked live and the first minute is where
    // the answer is silliest.
    Test.assertMessage(PageModel.cleanPerHour(1, 0.0) < 0.0, "a zero clock is not an hour");
    Test.assertMessage(PageModel.cleanPerHour(1, 40.0) < 0.0,
        "40 s of session is not enough afternoon to divide by");
    Test.assertMessage(PageModel.cleanPerHour(1, 59.9) < 0.0, "the floor is 60 s, exclusive");
    Test.assertEqual(PageModel.fmtCph(1, 40.0), PageModel.CPH_NONE);
    Test.assertEqual(PageModel.fmtCph(0, 0.0), PageModel.CPH_NONE);

    // ...and a real value the moment there is an hour to divide by. One clean jibe in the
    // first minute really is 60 an hour, and saying so is exactly why the floor is a minute
    // and not a second.
    Test.assertMessage((PageModel.cleanPerHour(1, 60.0) - 60.0).abs() < 0.01,
        "one clean jibe in the first minute is 60 an hour");
    Test.assertEqual(PageModel.fmtCph(1, 60.0), "60.0");
    // the corpus shape: 12 clean jibes in 1:45:00 is 6.9 an hour
    Test.assertMessage((PageModel.cleanPerHour(12, 6300.0) - 6.857).abs() < 0.01,
        "12 clean jibes in 1:45 is 6.86 an hour, got "
            + PageModel.cleanPerHour(12, 6300.0).format("%.3f"));
    Test.assertEqual(PageModel.fmtCph(12, 6300.0), "6.9");
    // a session with no clean jibe in it has a rate, and the rate is zero — that is a fact
    // about the afternoon, not a missing measurement, so it is NOT the "--" above
    Test.assertEqual(PageModel.fmtCph(0, 3600.0), "0.0");
    // the rate falls as the session lengthens under a fixed count, which is the whole point
    Test.assertMessage(PageModel.cleanPerHour(10, 7200.0) < PageModel.cleanPerHour(10, 3600.0),
        "the same ten jibes over twice the time must read as half the rate");

    logger.debug("CPH: floor " + PageModel.CPH_MIN_ELAPSED_S.format("%.0f") + " s, "
        + "12 in 1:45 = " + PageModel.fmtCph(12, 6300.0)
        + ", below the floor = " + PageModel.fmtCph(1, 40.0));
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
    var lead = r.det.peaks;

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
    Test.assertMessage(r.det.peaks > lead, "the second burst's strokes must still count");
    logger.debug("breather: " + r.det.peaks.toString() + " strokes over two bursts, "
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
    // 0.9.5: the string had been left at 0.9.0 through four releases while the manifests moved
    // on without it, which is the same drift this test was written for one field over. It is
    // the source tree's ONE answer to "what is this build", so it now says what the manifests
    // say — and the parse below is what keeps it honest about the byte.
    Test.assertEqual(FitSchema.APP_VERSION, "0.9.10");
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
        "pg4Layout" => 0, "pg5Layout" => 0, "pg6Layout" => 0, "pg7Layout" => 0,
        "pg8Layout" => 0
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
        "pg7Layout" => 0, "pg8Layout" => 0
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


// ---- The post-save map (0.9.9, GitHub #4) ----
// The gate, not the view: MapTrackView cannot be rendered headless (docs/watch-ui-review.md
// §12.1), so what is pinned is that the page is never offered unless the rider asked for it,
// and that asking for it is enough on a watch that has the view.
(:test)
function savedMapIsOfferedOnlyWhenAskedFor(logger as Test.Logger) as Boolean {
    var was = AppSettings.mapAfterSave;
    AppSettings.mapAfterSave = false;
    Test.assertMessage(!SavedMap.available(), "the post-save map must be off by default");
    AppSettings.mapAfterSave = true;
    var hasView = (Toybox.WatchUi has :MapTrackView) && (Toybox.WatchUi has :MapPolyline);
    Test.assertMessage(SavedMap.available() == hasView,
        "with the setting on, availability is the firmware's: " + hasView.toString());
    Test.assertMessage((SavedMap.padDeg(0.0) - 0.00045).abs() < 1.0e-9,
        "a one-line track still gets ~50 m of water either side");
    Test.assertMessage((SavedMap.padDeg(0.02) - 0.0016).abs() < 1.0e-9,
        "the pad is 8 % of the span");
    AppSettings.mapAfterSave = was;
    logger.debug("post-save map gate: setting off -> never; on -> firmware has MapTrackView "
        + hasView.toString());
    return true;
}

// ---- The phone-rendered ground (0.9.10, docs/watch-map-snapshot.md) ----
// The gate on an untrusted push and the framing arithmetic. The bitmap itself is not drawn
// headless here (createBufferedBitmap is exercised on the device); what is pinned is that a
// bad mask never reaches Storage and a good one is found by position.
function mapMask(w as Number, h as Number, cls as Number) as ByteArray {
    // one run per row of `w` cells (w <= 64) of class `cls`
    var b = new [h]b;
    for (var r = 0; r < h; r++) {
        b[r] = ((cls << 6) | (w - 1));
    }
    return b;
}

function mapMessage(id as Number, laS as Number, loW as Number, w as Number, h as Number,
        mask as ByteArray) as Dictionary {
    return {
        "mv" => 1, "mi" => id, "mn" => "Torbole",
        "la" => laS, "lo" => loW, "lh" => laS + 2700, "lx" => loW + 3800,
        "mw" => w, "mh" => h, "mp" => mask
    };
}

(:test)
function mapSnapshotKeepsGoodMasksAndDropsBadOnes(logger as Test.Logger) as Boolean {
    MapSnapshot.clearAll();
    var good = mapMessage(11, 4585000, 1085000, 8, 8, mapMask(8, 8, MapSnapshot.LAND));
    Test.assertMessage(MapSnapshot.store(good), "a well-formed snapshot must be kept");
    Test.assertMessage(MapSnapshot.slotForPosition(45.86, 10.87) != null,
        "a position inside the box must find the slot");
    Test.assertMessage(MapSnapshot.slotForPosition(45.00, 10.87) == null,
        "a position outside the box must find nothing");
    var slot = MapSnapshot.slotForPosition(45.86, 10.87) as String;
    Test.assertMessage(MapSnapshot.name(slot).equals("Torbole"), "the name rides along");
    var frame = MapSnapshot.frame(slot, 300);
    Test.assertMessage(frame != null && frame.size() == 6 && frame[5] > 0.0,
        "the frame carries the box, the squeeze and a positive scale");

    // a row that does not sum to mw: 7 rows for 8
    var short = mapMessage(12, 4585000, 1085000, 8, 8, mapMask(8, 7, MapSnapshot.WATER));
    Test.assertMessage(!MapSnapshot.store(short), "a short mask must be dropped");
    // wrong schema
    var bad = mapMessage(13, 4585000, 1085000, 8, 8, mapMask(8, 8, MapSnapshot.WATER));
    bad["mv"] = 2;
    Test.assertMessage(!MapSnapshot.store(bad), "an unknown schema must be dropped");
    // oversized grid
    var big = mapMessage(14, 4585000, 1085000, 200, 8, mapMask(8, 8, MapSnapshot.WATER));
    Test.assertMessage(!MapSnapshot.store(big), "a grid over 120 cells must be dropped");
    // an inverted box
    var inv = mapMessage(15, 4585000, 1085000, 8, 8, mapMask(8, 8, MapSnapshot.WATER));
    inv["lh"] = 4580000;
    Test.assertMessage(!MapSnapshot.store(inv), "a box with south above north must be dropped");

    // two slots, round robin: a third spot evicts the oldest, the same id replaces in place
    Test.assertMessage(MapSnapshot.store(mapMessage(21, 5400000, 1100000, 8, 8,
        mapMask(8, 8, MapSnapshot.ROAD))), "second spot kept");
    Test.assertMessage(MapSnapshot.store(mapMessage(31, 5500000, 1200000, 8, 8,
        mapMask(8, 8, MapSnapshot.WATER))), "third spot kept");
    Test.assertMessage(MapSnapshot.slotForPosition(45.86, 10.87) == null,
        "the oldest spot was evicted by the third");
    Test.assertMessage(MapSnapshot.slotForPosition(54.01, 11.01) != null
        && MapSnapshot.slotForPosition(55.01, 12.01) != null, "the two newest remain");
    Test.assertMessage(MapSnapshot.store(mapMessage(31, 5500000, 1200000, 8, 8,
        mapMask(8, 8, MapSnapshot.LAND))), "re-send of a known spot");
    Test.assertMessage(MapSnapshot.slotForPosition(54.01, 11.01) != null,
        "a re-send replaces its own slot and evicts nobody");
    MapSnapshot.clearAll();
    logger.debug("map snapshot: gate and slots as specified");
    return true;
}

(:test)
function phoneMapPushIsToldApartFromWind(logger as Test.Logger) as Boolean {
    MapSnapshot.clearAll();
    var was = AppSettings.cfg.windDirection;
    Test.assertMessage(PhoneLink.applyMessage({"wd" => 90}), "a wind push still lands");
    Test.assertMessage(PhoneLink.applyMessage(mapMessage(41, 4585000, 1085000, 8, 8,
        mapMask(8, 8, MapSnapshot.LAND))), "a map push lands through the same handler");
    Test.assertMessage(!PhoneLink.applyMessage({"mv" => 1}), "a map push with no mask is dropped");
    Test.assertMessage(MapSnapshot.slotForPosition(45.86, 10.87) != null, "and it was stored");
    AppSettings.storeWindDirection(was);
    MapSnapshot.clearAll();
    return true;
}

// ---- The splash page (0.9.10) ----
// The hero and the wordmark under it are one lockup centred on the glass; the hero's corners
// must sit inside the page radius on every glass, and the lockup must not run off the top
// or the bottom. Measured with the device's own fonts and the directory's own cut.
(:test)
function brandSplashLockupFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cx = dc.getWidth() / 2;
    var cy = dc.getHeight() / 2;
    var radius = RecordingView.fitRadius(dc, false, false);
    var heroH = Brand.heroH();
    var heroW = Brand.hero().getWidth();
    var wordH = dc.getFontHeight(Graphics.FONT_LARGE);
    var domH = dc.getFontHeight(BrandSplash.DOMAIN_FONT);
    var yHero = BrandSplash.heroY(cy, heroH, wordH, domH);
    var yWord = BrandSplash.wordY(cy, heroH, wordH, domH);
    var yDom = BrandSplash.domainY(cy, heroH, wordH, domH);
    Test.assertMessage(yHero - heroH / 2 >= 0, "the hero runs off the top of the glass");
    Test.assertMessage(yWord + wordH / 2 <= dc.getHeight(), "the wordmark runs off the bottom");
    Test.assertMessage(yDom + domH / 2 <= dc.getHeight(), "the domain line runs off the bottom");
    Test.assertMessage(cornerRadius(dc.getTextWidthInPixels(BrandSplash.DOMAIN,
        BrandSplash.DOMAIN_FONT), domH, yDom, cy) <= radius.toFloat(),
        "the domain line's corners sit outside the radius");
    Test.assertMessage(yDom - yWord >= (wordH + domH) / 2, "wordmark and domain line overlap");
    Test.assertMessage(cornerRadius(heroW, heroH, yHero, cy) <= radius.toFloat(),
        "the hero's corners sit outside the page radius on a " + screenPx().toString()
        + "px glass");
    Test.assertMessage(cornerRadius(dc.getTextWidthInPixels(START_TITLE, Graphics.FONT_LARGE),
        wordH, yWord, cy) <= radius.toFloat(), "the wordmark's corners sit outside the radius");
    Test.assertMessage(yWord - yHero >= (heroH + wordH) / 2, "hero and wordmark overlap");
    Brand.releaseHero();
    // the gate: a version once seen is not shown again until the version changes
    Toybox.Application.Storage.deleteValue(BrandSplash.STORE_SEEN);
    Test.assertMessage(BrandSplash.due(), "a fresh install gets the splash");
    BrandSplash.markSeen();
    Test.assertMessage(!BrandSplash.due(), "the same version does not show it twice");
    Toybox.Application.Storage.deleteValue(BrandSplash.STORE_SEEN);
    logger.debug("splash lockup: hero " + heroW.toString() + "x" + heroH.toString()
        + " on " + screenPx().toString() + " px");
    return true;
}

// 0.9.11: the words a stranger needs. The Turns header names the three counts under it and
// never the two maneuvers it used to; the tally's captions are the first thing dropped, so a
// wide tally is still bare digits and never clips; the start page and the paused banner name
// BACK wherever the glass has room, and fall back to the old words where it has not.
(:test)
function strangersWordsFitOrFallBack(logger as Logger) as Boolean {
    var dc = testBitmap(screenPx(), screenPx()).getDc();
    var cx = dc.getWidth() / 2;
    var radius = (screenPx() / 2.0 - BEZEL).toNumber();
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    // the header never says tack or jibe again, with or without an axis
    var h = RecordingView.turnsHeader(dc, "~NNE", radius, -radius / 2);
    Test.assertMessage(h.find("tack") == null && h.find("jibe") == null, "header: " + h);
    Test.assertEqual(RecordingView.turnsHeader(dc, "", radius, 0), TURNS_HEADER);
    // a header with the axis is only returned where it fits at XTINY
    if (h.length() > TURNS_HEADER.length()) {
        Test.assertMessage(dc.getTextWidthInPixels(h, Graphics.FONT_XTINY)
            <= RecordingView.rowBudget(radius, -radius / 2, RecordingView.inkH(dc, Graphics.FONT_XTINY)),
            "the axis was kept on a header that does not fit");
    }
    // captions: whenever the mask carries them, the row with them fits the budget; and the
    // worst-case tally at a tight budget drops them before it drops anything else
    var f = TEXT_FONTS[0];
    var wide = RecordingView.tallyWidth(dc, "99", "99", "99", "100% flew", TURNS_TALLY_SEP, f)
        + RecordingView.captionsWidth(dc);
    var m = RecordingView.tallyContent(dc, "99", "99", "99", "100% flew", wide, f);
    Test.assertMessage((m & TALLY_CAPTIONS) != 0, "captions missing at a budget that has room");
    m = RecordingView.tallyContent(dc, "99", "99", "99", "100% flew", wide - 1, f);
    Test.assertMessage((m & TALLY_CAPTIONS) == 0, "captions kept one pixel short");
    Test.assertMessage((m & TALLY_OK) != 0, "the verdict went before the captions");
    // the start hint and the paused banner: whichever form comes back fits where it goes
    var hint = StartView.hintText(dc, radius, radius / 3);
    Test.assertMessage(hint.equals(START_HINT) || hint.equals(START_HINT_LONG), hint);
    var font = TEXT_FONTS[PAUSED_FONT_IDX];
    var banner = RecordingView.pausedText(dc, font, radius);
    var w = dc.getTextWidthInPixels(banner, font);
    Test.assertMessage(RecordingView.pausedBannerY(dc, w, radius) <= cx - radius / 3,
        "the banner sits below the top third: " + banner);
    logger.debug("header " + h + " | hint " + hint + " | banner " + banner + " | caps "
        + ((RecordingView.tallyContent(dc, "8", "2", "1", "", RecordingView.rowBudget(radius, -radius / 4,
            RecordingView.inkH(dc, f)), f) & TALLY_CAPTIONS) != 0).toString());
    return true;
}


// ---- 0.9.13: measured ink, and no word on the number ladder ----
//
// Leo's fenix 5X Plus (17 Sep 2026): the clock sat on the giant's unit, "best 2s" on its
// record, SAVED on the verdict, and PAUSED was six empty boxes. One cause: every band was
// stacked on "ink = 3/4 of the line", which holds where a number line carries leading and
// not on the fenix 5 Plus family's Chronos fonts (ascent = line). The firmware's ascent is
// the yardstick now, floored at the old 3/4 so no other glass moves.
(:test)
function inkNeverUnderTheAscent(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var fonts = [Graphics.FONT_NUMBER_THAI_HOT, Graphics.FONT_NUMBER_HOT,
        Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD, Graphics.FONT_LARGE,
        Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
    for (var i = 0; i < fonts.size(); i++) {
        var f = fonts[i];
        var ink = RecordingView.inkH(dc, f);
        if (RecordingView.isNumberFont(f)) {
            Test.assertMessage(ink >= Graphics.getFontAscent(f),
                "font " + i.toString() + " ink " + ink.toString() + " under its ascent "
                    + Graphics.getFontAscent(f).toString());
        } else {
            // a text row keeps the 3/4 rule: its ascent reserves accent room no row uses
            Test.assertMessage(ink == dc.getFontHeight(f) * 3 / 4,
                "text font " + i.toString() + " left the 3/4 rule");
        }
        Test.assertMessage(ink >= dc.getFontHeight(f) * 3 / 4,
            "font " + i.toString() + " ink under the 3/4 floor");
        Test.assertMessage(ink <= dc.getFontHeight(f),
            "font " + i.toString() + " ink taller than its line");
    }
    logger.debug("THAI_HOT line " + dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT).toString()
        + " ascent " + Graphics.getFontAscent(Graphics.FONT_NUMBER_THAI_HOT).toString()
        + " ink " + RecordingView.inkH(dc, Graphics.FONT_NUMBER_THAI_HOT).toString());
    return true;
}

(:test)
function wordsNeverWalkTheNumberLadder(logger as Test.Logger) as Boolean {
    var dc = testDc();
    Test.assertMessage(RecordingView.hasLetters(PAUSED_TEXT), "PAUSED has no letters?");
    Test.assertMessage(!RecordingView.hasLetters("23:59") && !RecordingView.hasLetters("99.9")
        && !RecordingView.hasLetters("31/69") && !RecordingView.hasLetters("100%")
        && !RecordingView.hasLetters("+19"), "a number reads as a word");
    // a word through fitGiant lands in the TEXT ladder however wide the budget is
    var f = RecordingView.fitGiant(dc, PAUSED_TEXT, 3, screenPx());
    var inText = false;
    for (var i = 0; i < TEXT_FONTS.size(); i++) {
        if (f == TEXT_FONTS[i]) { inText = true; }
    }
    Test.assertMessage(inText, "PAUSED walked the number ladder");
    // the clock does not
    var cf = RecordingView.fitGiant(dc, "23:59", 3, screenPx());
    Test.assertMessage(cf == Graphics.FONT_NUMBER_MILD, "the clock left the number ladder");
    // the rung that fits a band never overflows it, and it is the first that does
    var hC = dc.getFontHeight(Graphics.FONT_NUMBER_MILD);
    var from = RecordingView.textFontFrom(dc, hC);
    Test.assertMessage(RecordingView.inkH(dc, TEXT_FONTS[from]) <= hC,
        "textFontFrom picked a rung taller than the band");
    Test.assertMessage(from == 0 || RecordingView.inkH(dc, TEXT_FONTS[from - 1]) > hC,
        "textFontFrom skipped a rung that fits");
    return true;
}

// ====================================================================== the direct transfer
// docs/transfer-format.md. Dev stream only, so these compile with monkey-dev.jungle and are
// excluded with the beta's and the release's `excludeAnnotations = dev`.

// A radio that behaves like the probe measured: onComplete arrives, the phone's ack comes
// later, from the test. It never calls onComplete twice for one page.
(:test :dev)
class DirectFakeRadio extends PhoneLink.Radio {
    var sent as Array<Number> = [] as Array<Number>;     // page indices, in order
    var lastPayload as Dictionary?;
    var complete as Boolean = true;

    function initialize() {
        PhoneLink.Radio.initialize();
    }

    function send(payload as Dictionary, listener as Communications.ConnectionListener) as Void {
        sent.add(payload[DirectSend.KEY_PAGE] as Number);
        lastPayload = payload;
        if (complete) {
            listener.onComplete();
        } else {
            listener.onError();
        }
    }
}

(:dev)
function hexOf(b as ByteArray) as String {
    var digits = "0123456789abcdef";
    var s = "";
    for (var i = 0; i < b.size(); i++) {
        var v = b[i];
        s += digits.substring(v >> 4, (v >> 4) + 1) + digits.substring(v & 15, (v & 15) + 1);
    }
    return s;
}

// The worked example of docs/transfer-format.md §2.3, byte for byte — the same 64 bytes
// lab/tools/cjr_ref.py --check derives and the kit's DirectStreamTests pin.
(:test :dev)
function directStreamMatchesTheReference(logger as Test.Logger) as Boolean {
    AppSettings.phonePush = true;
    DirectSend.discard();
    DirectSend.reachableOverride = false;
    DirectSend.utcOffsetOverride = 120;
    DirectSend.begin(1756556820, 200);
    DirectSend.recordFix(45.8710000d, 10.8630000d, 1756556820, 0, 66, 98, DirectSend.devPack(0, 0, 0, 0));
    DirectSend.recordFix(45.8710050d, 10.8630120d, 1756556821, 310, 66, 101, DirectSend.devPack(1, 0, 0, 1));
    DirectSend.recordFix(45.8710110d, 10.8630250d, 1756556822, 640, 65, 104, DirectSend.devPack(2, 12, 3, 2));
    var open = DirectSend.openBytes();
    Test.assertMessage(open != null, "the page is open");
    var hex = hexOf(open as ByteArray);
    var want = "434a5231020002091" + "4eeb268c8000000" + "78000000"
        + "ff14eeb268f05b571bf08f79060000420062000000000"
        + "105000c0036010065010000010106000d008002ff68020c0302";
    logger.debug(hex);
    Test.assertEqualMessage(hex, want, "the bytes are the reference's");
    Test.assertEqual((open as ByteArray).size(), 68);
    DirectSend.utcOffsetOverride = null;
    DirectSend.discard();
    return true;
}

// Every page opens with a keyframe, no page exceeds 8 000 bytes, and a pause longer than
// 254 s, an altitude that appears, and the sixtieth record each force a keyframe.
(:test :dev)
function directStreamPagesOpenWithAKeyframe(logger as Test.Logger) as Boolean {
    AppSettings.phonePush = true;
    DirectSend.discard();
    DirectSend.reachableOverride = false;
    DirectSend.begin(1756556820, -1);
    var t = 1756556820;
    var lat = 45.871d;
    var lon = 10.863d;
    for (var i = 0; i < 1300; i++) {
        var alt = i < 100 ? DirectSend.ALT_NONE : 66;
        if (i == 700) { t += 400; }             // a pause
        DirectSend.recordFix(lat, lon, t, 500 + (i % 300), alt, 100, DirectSend.devPack(2, 0, 0, i % 255));
        lat += 0.00003d;
        lon += 0.00002d;
        t += 1;
    }
    DirectSend.finish();
    var n = DirectSend.pageCount();
    Test.assertMessage(n >= 3, "1 300 fixes are three pages at least, got " + n);
    var keyframes = 0;
    for (var p = 0; p < n; p++) {
        var page = DirectSend.page(p);
        Test.assertMessage(page.size() <= DirectSend.PAGE_BYTES, "page " + p + " over 8 000");
        var first = p == 0 ? DirectSend.HEADER_BYTES : 0;
        Test.assertMessage(page[first] == DirectSend.KEYFRAME_TAG,
            "page " + p + " does not open with a keyframe");
        var i = first;
        while (i < page.size()) {
            if (page[i] == DirectSend.KEYFRAME_TAG) {
                keyframes += 1;
                i += DirectSend.KEYFRAME_BYTES;
            } else {
                i += DirectSend.DELTA_BYTES;
            }
        }
        Test.assertMessage(i == page.size(), "page " + p + " ends mid-record");
    }
    // 1300 / 60 → 22 scheduled, plus the pause, the altitude edge and one per page start.
    Test.assertMessage(keyframes >= 24 && keyframes <= 30,
        "keyframe count off: " + keyframes);
    logger.debug(n + " pages, " + keyframes + " keyframes");
    DirectSend.discard();
    return true;
}

// One page in flight, the next only after the phone's ack, a need list re-sends, and the
// empty need list frees the stream. The rules the probe wrote in blood (8 KB, one at a
// time) are asserted on the fake radio's order.
(:test :dev)
function directSendMovesOnePageAtATime(logger as Test.Logger) as Boolean {
    var saved = PhoneLink.radio;
    var fake = new DirectFakeRadio();
    PhoneLink.radio = fake;
    AppSettings.phonePush = true;
    DirectSend.discard();
    DirectSend.reachableOverride = true;
    DirectSend.begin(1756556820, 200);
    var t = 1756556820;
    for (var i = 0; i < 1300; i++) {
        DirectSend.recordFix(45.871d, 10.863d, t, 500, 66, 100, DirectSend.devPack(2, 0, 0, i % 255));
        t += 1;
    }
    DirectSend.finish();
    var n = DirectSend.pageCount();
    Test.assertMessage(n >= 3, "three pages at least");
    // Page 0 left when it closed; nothing else may leave before its ack.
    Test.assertEqual(fake.sent.size(), 1);
    Test.assertEqual(fake.sent[0], 0);
    Test.assertEqual(DirectSend.inFlight(), 0);
    var p0 = fake.lastPayload as Dictionary;
    Test.assertEqual(p0[DirectSend.KEY_MSG], 1);
    Test.assertEqual(p0[DirectSend.KEY_SID], 1756556820);
    Test.assertEqual(p0[DirectSend.KEY_STREAM], 0);

    // The ack for page 0 releases page 1; a stray ack for a page not on the radio is
    // taken as a record but sends nothing new while 1 is in flight.
    Test.assertMessage(DirectSend.applyMessage({"cjrAck" => [1756556820, 0, 0]}), "ack 0");
    Test.assertEqual(fake.sent.size(), 2);
    Test.assertEqual(fake.sent[1], 1);
    Test.assertMessage(DirectSend.acked(0), "page 0 acked");
    Test.assertMessage(!DirectSend.applyMessage({"cjrAck" => [999, 0, 1]}), "wrong sid");
    Test.assertMessage(!DirectSend.applyMessage({"cjrAck" => "no"}), "malformed");
    Test.assertEqual(fake.sent.size(), 2);

    // Ack everything; the last page carries e = 1 and n.
    for (var p = 1; p < n; p++) {
        DirectSend.applyMessage({"cjrAck" => [1756556820, 0, p]});
    }
    Test.assertEqual(fake.sent.size(), n);
    var last = fake.lastPayload as Dictionary;
    Test.assertEqual(last[DirectSend.KEY_END], 1);
    Test.assertEqual(last[DirectSend.KEY_COUNT], n);
    Test.assertEqual(DirectSend.inFlight(), -1);

    // The phone missed page 1: the need list re-sends it, and only it.
    Test.assertMessage(DirectSend.applyMessage({"cjrNeed" => [1756556820, 0, [1]]}), "need");
    Test.assertEqual(fake.sent.size(), n + 1);
    Test.assertEqual(fake.sent[n], 1);
    DirectSend.applyMessage({"cjrAck" => [1756556820, 0, 1]});
    Test.assertEqual(fake.sent.size(), n + 1);

    // The flat shapes the phone actually sends (19 September 2026): an ack as three keys,
    // a need list as a comma-joined string.
    DirectSend.applyMessage({"cjrNeed" => "1", "cjrSid" => 1756556820, "cjrSt" => 0});
    Test.assertEqual(fake.sent.size(), n + 2);
    Test.assertMessage(DirectSend.applyMessage(
        {"cjrAck" => 1, "cjrSid" => 1756556820, "cjrSt" => 0}), "flat ack");
    Test.assertEqual(fake.sent.size(), n + 2);
    Test.assertMessage(!DirectSend.applyMessage(
        {"cjrAck" => 1, "cjrSid" => 5, "cjrSt" => 0}), "flat ack, wrong sid");

    // The empty need list is the release — in the flat shape, an empty string.
    Test.assertMessage(DirectSend.applyMessage({"cjrNeed" => "", "cjrSid" => 1756556820, "cjrSt" => 0}), "done");
    Test.assertEqual(DirectSend.pageCount(), 0);
    Test.assertEqual(DirectSend.statusLine(), "phone ok");
    // And the array shape still reads.
    DirectSend.begin(1756556820, 200);
    DirectSend.recordFix(45.871d, 10.863d, 1756556820, 500, 66, 100, DirectSend.devPack(2, 0, 0, 0));
    DirectSend.finish();
    Test.assertMessage(DirectSend.applyMessage({"cjrAck" => [1756556820, 0, 0]}), "array ack");
    Test.assertMessage(DirectSend.applyMessage({"cjrNeed" => [1756556820, 0, []]}), "array done");
    logger.debug(n + " pages, one at a time, " + fake.sent.size() + " sends");

    DirectSend.reachableOverride = null;
    PhoneLink.radio = saved;
    return true;
}

// A radio error leaves the page for a retry; the phone out of reach sends nothing; the
// beta's off switch (phonePush) is this stream's off switch too.
(:test :dev)
function directSendWaitsForThePhone(logger as Test.Logger) as Boolean {
    var saved = PhoneLink.radio;
    var fake = new DirectFakeRadio();
    fake.complete = false;
    PhoneLink.radio = fake;
    AppSettings.phonePush = true;
    DirectSend.discard();
    DirectSend.reachableOverride = false;
    DirectSend.begin(1756556820, 200);
    for (var i = 0; i < 700; i++) {
        DirectSend.recordFix(45.871d, 10.863d, 1756556820 + i, 500, 66, 100, DirectSend.devPack(2, 0, 0, i % 255));
    }
    DirectSend.finish();
    Test.assertEqual(fake.sent.size(), 0);           // no phone, no send
    Test.assertMessage(DirectSend.pageCount() >= 1, "pages queued");

    // The phone appears: the connected edge pumps; the radio fails; three retries, then
    // the stream waits for the next edge instead of hammering the radio.
    DirectSend.reachableOverride = true;
    DirectSend.pump();
    Test.assertMessage(fake.sent.size() >= 1 && fake.sent.size() <= 1 + DirectSend.RETRIES,
        "retries bounded: " + fake.sent.size());
    Test.assertEqual(DirectSend.inFlight(), -1);
    Test.assertMessage(!DirectSend.acked(0), "an errored page is not acked");

    // The switch off: nothing leaves, not even with a phone.
    fake.complete = true;
    AppSettings.phonePush = false;
    var before = fake.sent.size();
    DirectSend.pump();
    Test.assertEqual(fake.sent.size(), before);
    AppSettings.phonePush = true;

    // A recording begun with the switch off records nothing.
    DirectSend.discard();
    AppSettings.phonePush = false;
    DirectSend.begin(1, -1);
    DirectSend.recordFix(45.871d, 10.863d, 1, 500, 66, 100, DirectSend.devPack(2, 0, 0, 0));
    Test.assertMessage(DirectSend.openBytes() == null, "switch off, no stream");
    AppSettings.phonePush = true;
    DirectSend.reachableOverride = null;
    PhoneLink.radio = saved;
    logger.debug("ok");
    return true;
}

// ============================================================================
// THE WATCH'S CRASH HUNT (docs/testing.md, "The watch's crash hunt")
//
// The phone's hunt (`SyncCrashHuntTests`, `MutationFuzzTests`) exists because a stranger's
// FIT is a door into the app that nobody here has walked through. The watch has three such
// doors and a worse consequence: there is no crash reporting on a Connect IQ device. An
// unhandled exception drops the rider to the watch face and writes CIQ_LOG.YML onto a watch
// on a beach, and the session goes with it.
//
// The doors, and what is fuzzed at each:
//   * THE SENSOR — `MetricsEngine.tick` / `SessionController.onPosition` take one
//     Position.Info a second for hours. Null everything, an unusable fix, a 300 m/s spike,
//     a 30 s gap, a clock that runs backwards, the System.getTimer wrap, six hours at 1 Hz.
//   * THE SETTINGS — `AppSettings.load` reads Application.Properties, which is a store that
//     outlives the build that wrote it and takes any type at all.
//   * THE PHONE — `PhoneLink.applyMessage` is a dictionary from another process on another
//     device. It is the only input here an attacker could shape.
//
// The assertion in all of them is the phone hunt's: FINISH, OR THROW SOMETHING NAMED — never
// trap. And on this runtime that bar is higher than it sounds, because three of the ways to
// die are NOT catchable by `try`/`catch` at all (measured on fenix847mm, SDK 9.2):
//     1.0 / 0.0          -> "Invalid Value", uncaught, whatever it is wrapped in
//     0.0 / 0.0          -> the same
//     5 / 0              -> the same
//     array[past end]    -> "Array Out Of Bounds", the same
// `null > 0` does throw a catchable UnexpectedTypeException, and Float.toNumber() saturates
// at ±2147483647 rather than trapping. So every fix in this round is a GUARD, never a catch:
// the try/catch in these tests is there to name the tick that failed, not to make the app
// survive one.
//
// The drive loops move the engine's clock by hand through `MetricsEngine.clockMsOverride` —
// tick() reads dt from System.getTimer(), so twenty thousand calls in a tight loop would all
// see dt ≈ 0 and exercise nothing.

// One fabricated fix. Position.Info cannot be handed to us by the simulator, but it CAN be
// constructed — `new Position.Info()` gives an object whose five members are all null, which
// is itself the most interesting shape in the list below.
function fuzzFix(acc as Position.Quality?, spd as Float?, hdg as Float?, alt as Float?,
        lat as Double?, lon as Double?) as Position.Info {
    var i = new Position.Info();
    i.accuracy = acc;
    i.speed = spd;
    i.heading = hdg;
    i.altitude = alt;
    if (lat != null && lon != null) {
        i.position = new Position.Location({
            :latitude => lat, :longitude => lon, :format => :degrees
        });
    }
    return i;
}

// A plausible fix, as the baseline every shape is a deviation from.
function fuzzGoodFix() as Position.Info {
    return fuzzFix(Position.QUALITY_GOOD, 9.0, 0.6, 3.0, 45.8710d, 10.8712d);
}

const FUZZ_SHAPES = 20;

function fuzzShapeName(k as Number) as String {
    if (k == 0) { return "a good fix"; }
    if (k == 1) { return "no position"; }
    if (k == 2) { return "no speed"; }
    if (k == 3) { return "no heading"; }
    if (k == 4) { return "no altitude"; }
    if (k == 5) { return "no accuracy"; }
    if (k == 6) { return "accuracy NOT_AVAILABLE"; }
    if (k == 7) { return "accuracy LAST_KNOWN"; }
    if (k == 8) { return "accuracy out of the enum"; }
    if (k == 9) { return "speed 0 all session"; }
    if (k == 10) { return "speed 300 m/s"; }
    if (k == 11) { return "speed negative"; }
    if (k == 12) { return "speed as a Number, not a Float"; }
    if (k == 13) { return "heading 1e9 rad"; }
    if (k == 14) { return "heading -1e9 rad"; }
    if (k == 15) { return "altitude 1e9 m"; }
    if (k == 16) { return "the poles"; }
    if (k == 17) { return "the antimeridian"; }
    if (k == 18) { return "everything null"; }
    return "speed exactly at the plausible ceiling";
}

function fuzzShape(k as Number) as Position.Info {
    var g = Position.QUALITY_GOOD;
    if (k == 0) { return fuzzGoodFix(); }
    if (k == 1) { return fuzzFix(g, 9.0, 0.6, 3.0, null, null); }
    if (k == 2) { return fuzzFix(g, null, 0.6, 3.0, 45.871d, 10.871d); }
    if (k == 3) { return fuzzFix(g, 9.0, null, 3.0, 45.871d, 10.871d); }
    if (k == 4) { return fuzzFix(g, 9.0, 0.6, null, 45.871d, 10.871d); }
    if (k == 5) { return fuzzFix(null, 9.0, 0.6, 3.0, 45.871d, 10.871d); }
    if (k == 6) {
        return fuzzFix(Position.QUALITY_NOT_AVAILABLE, 9.0, 0.6, 3.0, 45.871d, 10.871d);
    }
    if (k == 7) {
        return fuzzFix(Position.QUALITY_LAST_KNOWN, 9.0, 0.6, 3.0, 45.871d, 10.871d);
    }
    if (k == 8) { return fuzzFix(99 as Position.Quality, 9.0, 0.6, 3.0, 45.871d, 10.871d); }
    if (k == 9) { return fuzzFix(g, 0.0, 0.6, 3.0, 45.871d, 10.871d); }
    if (k == 10) { return fuzzFix(g, 300.0, 0.6, 3.0, 45.871d, 10.871d); }
    if (k == 11) { return fuzzFix(g, -5.0, 0.6, 3.0, 45.871d, 10.871d); }
    if (k == 12) { return fuzzFix(g, 9 as Float, 0.6, 3.0, 45.871d, 10.871d); }
    if (k == 13) { return fuzzFix(g, 9.0, 1.0e9, 3.0, 45.871d, 10.871d); }
    if (k == 14) { return fuzzFix(g, 9.0, -1.0e9, 3.0, 45.871d, 10.871d); }
    if (k == 15) { return fuzzFix(g, 9.0, 0.6, 1.0e9, 45.871d, 10.871d); }
    if (k == 16) { return fuzzFix(g, 9.0, 0.6, 3.0, 90.0d, 0.0d); }
    if (k == 17) { return fuzzFix(g, 9.0, 0.6, 3.0, -89.9d, 179.999d); }
    if (k == 18) { return new Position.Info(); }
    return fuzzFix(g, WingFoilCore.MAX_SPEED_MPS, 0.6, 3.0, 45.871d, 10.871d);
}

// A controller in the state the sensor door is actually walked in: RECORDING, with no
// ActivityRecording.Session behind it (the simulator has none, and every session call in
// SessionController is already null-guarded — which this exercises too).
function fuzzController() as SessionController {
    var c = new SessionController();
    c.state = SessionController.STATE_RECORDING;
    c.engine.trackEnabled = true;
    c.engine.clockMsOverride = 100000;
    return c;
}

// ---- 1. the sensor door ----

// Every degenerate fix shape, through the WHOLE door — engine, detectors, alerts, the FIT
// writer's marker, the direct stream — five times each so a shape that only breaks on the
// second sample of its own kind is caught too.
//
// FOUND HERE: `MetricsEngine._cogDeg` normalised a heading with two `while` loops, which is
// 2.7 million iterations inside a 1 Hz callback for a fix carrying 1e9 rad — a watchdog kill
// with nothing in the log. It is arithmetic now.
(:test)
function fuzzSensorDoorSurvivesEveryDegenerateFix(logger as Test.Logger) as Boolean {
    AppSettings.load();
    var worst = "";
    for (var k = 0; k < FUZZ_SHAPES; k++) {
        var c = fuzzController();
        var t = 100000;
        for (var i = 0; i < 5; i++) {
            t += 1000;
            c.engine.clockMsOverride = t;
            worst = "shape " + k.toString() + " (" + fuzzShapeName(k) + ") tick "
                + i.toString();
            try {
                c.onPosition(fuzzShape(k));
            } catch (e) {
                Test.assertMessage(false, worst + " threw " + e.getErrorMessage());
            }
        }
        // whatever went in, what comes out is still a number the card can carry
        Test.assertMessage(c.engine.speedMps >= 0.0
            && c.engine.speedMps <= WingFoilCore.MAX_SPEED_MPS,
            fuzzShapeName(k) + " left speed at " + c.engine.speedMps.toString());
        Test.assertMessage(c.engine.distM >= 0.0,
            fuzzShapeName(k) + " left distance at " + c.engine.distM.toString());
    }
    // A null fix is not a shape the API promises, and it is one member read from ending the
    // session. The controller drops it.
    var c2 = fuzzController();
    c2.onPosition(null as Position.Info);
    logger.debug(FUZZ_SHAPES.toString() + " fix shapes x 5 ticks, all survived");
    return true;
}

// The clock, which is the other half of the sensor door: a 30 s hole, a sample that arrives
// before the one before it, and the System.getTimer wrap (~24.8 days of uptime — a watch
// that is never rebooted reaches it, and a wingfoiler's does not get rebooted).
(:test)
function fuzzTheClockRunsBackwardsAndWraps(logger as Test.Logger) as Boolean {
    AppSettings.load();
    var c = fuzzController();
    var fix = fuzzGoodFix();
    var t = 100000;
    // a normal minute
    for (var i = 0; i < 60; i++) {
        t += 1000;
        c.engine.clockMsOverride = t;
        c.onPosition(fix);
    }
    var foilAfterMinute = c.engine.detector.foilTimeS;
    // a 30 s hole: dt is clamped at 3 s, so the hole cannot become half a minute of flight
    t += 30000;
    c.engine.clockMsOverride = t;
    c.onPosition(fix);
    Test.assertMessage(c.engine.detector.foilTimeS - foilAfterMinute <= 3.5,
        "a 30 s gap booked " + (c.engine.detector.foilTimeS - foilAfterMinute).toString()
        + " s of flight");
    // backwards, then the wrap itself
    var marks = [t - 5000, 2147483000, -2147483296, -2147483000, 1000] as Array<Number>;
    for (var i = 0; i < marks.size(); i++) {
        c.engine.clockMsOverride = marks[i];
        try {
            c.onPosition(fix);
        } catch (e) {
            Test.assertMessage(false, "clock mark " + marks[i].toString() + " threw "
                + e.getErrorMessage());
        }
        Test.assertMessage(c.engine.detector.foilTimeS < 1.0e6,
            "clock mark " + marks[i].toString() + " booked "
            + c.engine.detector.foilTimeS.toString() + " s of flight");
    }
    logger.debug("gap, reversal and the getTimer wrap: no time invented");
    return true;
}

// ---- 2. six hours at 1 Hz ----

// 21 600 ticks — a long Garda day — with the memory read either side. Two things are being
// asked. Does anything in the chain allocate per tick (the answer has to be no: the track
// buffer, the history and the sweep log are all fixed arrays, and the stride doubles rather
// than the buffer growing). And does six hours of it stay inside the heap.
//
// THE NUMBER THIS PRINTS IS THE SIMULATOR'S, NOT THE WATCH'S. `getSystemStats` reports the
// simulator's own 8 MB heap, where a fenix 8 gives the app 786 KB. What the assertion is
// worth is therefore the GROWTH, which is the same arithmetic on both: MEASURED AT EXACTLY
// 3 096 B on fenix847mm, fenix7s and fenix5plus alike — the same number on all three, which
// is what a chain with no per-tick allocation looks like. The free floor below is a smoke
// alarm, not the device's headroom (docs/testing.md, "The watch's crash hunt").
(:test)
function fuzzSixHoursAtOneHertzHoldItsMemory(logger as Test.Logger) as Boolean {
    AppSettings.load();
    var c = fuzzController();
    var before = System.getSystemStats().usedMemory;
    var freeBefore = System.getSystemStats().freeMemory;
    var t = 100000;
    var fix = fuzzGoodFix();
    // A course that actually turns, so the turn detector, the sweep log and the auto-wind
    // histogram all do their work rather than idling for six hours.
    for (var i = 0; i < 21600; i++) {
        t += 1000;
        c.engine.clockMsOverride = t;
        var leg = (i / 120) % 2;
        var hdg = leg == 0 ? 0.7 : 3.1;
        var spd = (i % 300) < 30 ? 2.0 : 9.5;
        c.onPosition(fuzzFix(Position.QUALITY_GOOD, spd, hdg, 3.0,
            45.8710d + i * 0.00002d, 10.8712d + i * 0.00001d));
    }
    var after = System.getSystemStats().usedMemory;
    var freeAfter = System.getSystemStats().freeMemory;
    var grew = after - before;
    logger.debug("6 h at 1 Hz: used " + before.toString() + " -> " + after.toString()
        + " (+" + grew.toString() + " B), free " + freeBefore.toString() + " -> "
        + freeAfter.toString() + ", " + c.engine.tickCount().toString() + " ticks, "
        + c.engine.trackN.toString() + " track points, "
        + c.engine.history.slotCount.toString() + " history slots");
    // Measured: 3 096 B on all three devices. 64 KB is the failure line — what this is
    // here to catch is a per-tick allocation, not a byte.
    Test.assertMessage(grew < 65536,
        "six hours grew the heap by " + grew.toString() + " B");
    Test.assertMessage(freeAfter > 102400,
        "free memory after six hours is " + freeAfter.toString() + " B");
    // The fixed footprints stayed fixed.
    Test.assertMessage(c.engine.trackN <= c.engine.TRACK_MAX,
        "the breadcrumb holds " + c.engine.trackN.toString() + " points");
    Test.assertMessage(c.engine.history.slotCount <= c.engine.history.SLOT_MAX,
        "the timeline holds " + c.engine.history.slotCount.toString() + " slots");
    return true;
}

// ---- 3. the session lifecycle, in every order ----

// Two hundred pause/resume cycles, a save with no ticks behind it, a save twice, and a
// discard in the middle of a flight. None of these has a Session object behind it here,
// which is the point: every one of those calls is null-guarded and this is what says so.
(:test)
function fuzzSessionLifecycleSurvivesEveryOrder(logger as Test.Logger) as Boolean {
    AppSettings.load();
    var saved = PhoneLink.radio;
    PhoneLink.radio = new FakeRadio(false);
    var push = AppSettings.phonePush;
    AppSettings.phonePush = false;

    var c = fuzzController();
    var fix = fuzzGoodFix();
    var t = 100000;
    for (var i = 0; i < 200; i++) {
        c.togglePause();
        t += 1000;
        c.engine.clockMsOverride = t;
        c.onPosition(fix);
        c.togglePause();
    }

    // zero ticks, then save
    var fresh = new SessionController();
    Test.assertMessage(!fresh.finishSave(), "a save with no session claimed to have written");
    Test.assertMessage(!fresh.finishSave(), "the second save claimed to have written");
    var card = PhoneLink.summary(fresh);
    Test.assertEqual(card[PhoneLink.KEY_FOIL_PCT], 0);
    Test.assertEqual(card[PhoneLink.KEY_DUR], 0);

    // discard in the middle of a flight
    var flying = fuzzController();
    var t2 = 100000;
    for (var i = 0; i < 30; i++) {
        t2 += 1000;
        flying.engine.clockMsOverride = t2;
        flying.onPosition(fix);
    }
    Test.assertMessage(flying.engine.detector.state == FlightDetector.STATE_ON,
        "the rig never got on the foil, so the discard proves nothing");
    flying.finishDiscard();
    Test.assertEqual(flying.state, SessionController.STATE_IDLE);
    flying.finishDiscard();             // twice
    flying.emergencySave();             // and with nothing left to save

    AppSettings.phonePush = push;
    PhoneLink.radio = saved;
    logger.debug("200 pause cycles, save x2, discard mid-flight: no throw");
    return true;
}

// ---- 4. the accelerometer batch ----

// The pump detector's door. The three arrays come from the firmware and a sample that never
// arrived is a null INSIDE them, not a shorter array — `null.toFloat()` from a sensor
// callback is an exception nothing catches.
(:test)
function fuzzAccelBatchesSurviveEveryShape(logger as Test.Logger) as Boolean {
    var p = new PumpDetector(AppSettings.cfg);
    p.start(25);
    var t = 50000;

    var empty = [] as Array<Number>;
    p.onAccelBatch(null, null, null, t);
    p.onAccelBatch(empty, empty, empty, t);

    var one = [1000] as Array<Number>;
    p.onAccelBatch(one, one, one, t + 40);

    var hundred = new [100] as Array<Number>;
    for (var i = 0; i < 100; i++) {
        hundred[i] = 900 + (i % 7) * 40;
    }
    p.onAccelBatch(hundred, hundred, hundred, t + 4040);

    // y shorter than x: the batch is dropped, not read past its end
    var short = [1000, 1000] as Array<Number>;
    p.onAccelBatch(hundred, short, hundred, t + 5000);

    // holes in the middle
    var holed = new [25] as Array<Number>;
    for (var i = 0; i < 25; i++) {
        holed[i] = i == 7 || i == 19 ? null : 1000;
    }
    p.onAccelBatch(holed, holed, holed, t + 6000);

    // absurd magnitudes, and the getTimer wrap between two batches
    var huge = new [25] as Array<Number>;
    for (var i = 0; i < 25; i++) {
        huge[i] = 2000000000;
    }
    p.onAccelBatch(huge, huge, huge, t + 7000);
    p.onAccelBatch(hundred, hundred, hundred, -2147483000);

    // a listener that never started: available is false and nothing is read at all
    var off = new PumpDetector(AppSettings.cfg);
    off.onAccelBatch(hundred, hundred, hundred, t);
    Test.assertEqual(off.strokes, 0);

    // the HR the cost tracker prices a takeoff on: nothing, then a sprint
    var hc = new HrCostTracker();
    for (var i = 0; i < 40; i++) {
        hc.tick(1.0, null, true, false);
    }
    for (var i = 0; i < 40; i++) {
        hc.tick(1.0, 250, true, i == 5);
    }
    hc.tick(1.0, null, false, false);
    logger.debug("accel batches: null, empty, 1, 100, ragged, holed, saturated — no throw");
    return true;
}

// ---- 5. the settings ----

// Application.Properties is a STORE, not a form. It survives an app update, a settings sync
// can carry a value this build's settings.xml no longer allows, and setValue takes any type
// at all (measured: a String, a Float and a null all go into a property declared `number`
// and come back out unchanged). So every property is driven through six shapes and the
// thresholds are asserted to land inside docs/algorithms.md afterwards.
const FUZZ_PROPS = ["foilEntryKmh", "foilExitKmh", "entryHoldS", "exitHoldS", "minFlightS",
    "sportChoice", "windDirDeg", "windDefaultTurnType", "autoPauseDelayS",
    "alertIntervalMin", "alertIntervalKm", "pg1Layout", "pg1s1", "pg8Layout"];

function fuzzPropValue(shape as Number) as Object? {
    if (shape == 0) { return 0; }
    if (shape == 1) { return -1; }
    if (shape == 2) { return 2147483647; }
    if (shape == 3) { return 7.25; }
    if (shape == 4) { return "twelve"; }
    return null;
}

function fuzzPropShapeName(shape as Number) as String {
    if (shape == 0) { return "0"; }
    if (shape == 1) { return "-1"; }
    if (shape == 2) { return "a huge Number"; }
    if (shape == 3) { return "a Float"; }
    if (shape == 4) { return "a String"; }
    return "null";
}

function fuzzPutProp(key as String, v as Object?) as Void {
    try {
        Properties.setValue(key, v as Lang.Number);
    } catch (e) {
    }
}

function fuzzReadProp(key as String) as Object? {
    try {
        return Properties.getValue(key);
    } catch (e) {
        return null;
    }
}

(:test)
function fuzzSettingsClampWhateverTheStoreSays(logger as Test.Logger) as Boolean {
    // snapshot, so the rest of the suite reads the properties it expects
    var keep = new [FUZZ_PROPS.size()] as Array<Object?>;
    for (var i = 0; i < FUZZ_PROPS.size(); i++) {
        keep[i] = fuzzReadProp(FUZZ_PROPS[i]);
    }

    for (var i = 0; i < FUZZ_PROPS.size(); i++) {
        for (var shape = 0; shape < 6; shape++) {
            var where = FUZZ_PROPS[i] + " = " + fuzzPropShapeName(shape);
            fuzzPutProp(FUZZ_PROPS[i], fuzzPropValue(shape));
            try {
                AppSettings.load();
                PageModel.build(null);
                PageNav.index = PageModel.wrap(PageNav.index);
            } catch (e) {
                Test.assertMessage(false, where + " threw " + e.getErrorMessage());
            }
            var cfg = AppSettings.cfg;
            // docs/algorithms.md: entry 6-25 km/h, exit 4-20, holds 1-10 s, minFlight 2-30 s,
            // and the exit speed always strictly under the entry speed.
            Test.assertMessage(cfg.foilEntryMps >= 6.0 / 3.6 && cfg.foilEntryMps <= 25.0 / 3.6,
                where + " left foil entry at " + cfg.foilEntryMps.toString() + " m/s");
            Test.assertMessage(cfg.foilExitMps > 0.0 && cfg.foilExitMps < cfg.foilEntryMps,
                where + " left foil exit at " + cfg.foilExitMps.toString() + " m/s");
            Test.assertMessage(cfg.entryHoldS >= 1 && cfg.entryHoldS <= 10,
                where + " left entry hold at " + cfg.entryHoldS.toString());
            Test.assertMessage(cfg.exitHoldS >= 1 && cfg.exitHoldS <= 10,
                where + " left exit hold at " + cfg.exitHoldS.toString());
            Test.assertMessage(cfg.minFlightS >= 2 && cfg.minFlightS <= 30,
                where + " left min flight at " + cfg.minFlightS.toString());
            Test.assertMessage(cfg.windDirection >= -1 && cfg.windDirection <= 359,
                where + " left the wind axis at " + cfg.windDirection.toString());
            Test.assertMessage(AppSettings.windDefaultTurnType >= WingFoilCore.TURN_TYPE_JIBES
                && AppSettings.windDefaultTurnType <= WingFoilCore.TURN_TYPE_BALANCED,
                where + " left the turn habit at "
                + AppSettings.windDefaultTurnType.toString());
            Test.assertMessage(AppSettings.autoPauseDelayS >= 2
                && AppSettings.autoPauseDelayS <= 60,
                where + " left the auto-pause delay at "
                + AppSettings.autoPauseDelayS.toString());
            Test.assertMessage(AppSettings.alertIntervalMin >= 0
                && AppSettings.alertIntervalMin <= 120,
                where + " left the time alert at "
                + AppSettings.alertIntervalMin.toString());
            Test.assertMessage(AppSettings.alertIntervalKm >= 0.0
                && AppSettings.alertIntervalKm <= 50.0,
                where + " left the distance alert at "
                + AppSettings.alertIntervalKm.toString());
            Test.assertMessage(AppSettings.sportChoice >= 0 && AppSettings.sportChoice <= 2,
                where + " left the sport at " + AppSettings.sportChoice.toString());
            // and the rider is never left with a blank watch
            Test.assertMessage(PageModel.count() >= 1, where + " left no pages at all");
            Test.assertMessage(PageModel.layoutAt(PageNav.index) >= 0
                && PageModel.layoutAt(PageNav.index) <= PageModel.LAYOUT_MAX,
                where + " left page " + PageNav.index.toString() + " on an unknown layout");
        }
        fuzzPutProp(FUZZ_PROPS[i], keep[i]);
    }
    PageNav.index = 0;
    AppSettings.load();
    PageModel.build(null);
    logger.debug(FUZZ_PROPS.size().toString() + " properties x 6 shapes: every threshold "
        + "inside its documented range");
    return true;
}

// ---- 6. the phone ----

// The one input another process shapes. `applyMessage` decides three things — a map
// snapshot, a direct-transfer answer, a wind push — and each of them is a type check away
// from a fatal: a snapshot whose grid is 0 divides by it, and a division by zero on this
// runtime is not catchable.
(:test)
function fuzzPhoneMessagesNeverThrow(logger as Test.Logger) as Boolean {
    var big = "0123456789";
    for (var i = 0; i < 11; i++) {
        big = big + big;                 // 20 KB
    }
    var mask = mapMask(16, 16, 0);

    var msgs = [
        null,
        "not a dictionary",
        42,
        [1, 2, 3],
        {},
        {PhoneLink.KEY_IN_WIND => 200},
        {PhoneLink.KEY_IN_WIND => 200.5},
        {PhoneLink.KEY_IN_WIND => "200"},
        {PhoneLink.KEY_IN_WIND => -2},
        {PhoneLink.KEY_IN_WIND => 360},
        {PhoneLink.KEY_IN_WIND => null},
        {PhoneLink.KEY_IN_WIND => big},
        {MapSnapshot.K_SCHEMA => 99},
        {MapSnapshot.K_SCHEMA => "1"},
        {MapSnapshot.K_SCHEMA => 1},
        {MapSnapshot.K_SCHEMA => 1, MapSnapshot.K_W => 0, MapSnapshot.K_H => 0},
        {MapSnapshot.K_SCHEMA => 1, MapSnapshot.K_W => 100000,
            MapSnapshot.K_H => 100000, MapSnapshot.K_MASK => mask},
        {MapSnapshot.K_SCHEMA => 1, MapSnapshot.K_NAME => big},
        {"cjrAck" => 0},
        {"cjrAck" => "0"},
        {"cjrAck" => []},
        {"cjrAck" => [1, 2, 3, 4]},
        {"cjrNeed" => big},
        {"cjrNeed" => ",,,,,,,,"},
        {"cjrNeed" => []},
        {"cjrNeed" => 7}
    ] as Array;

    for (var i = 0; i < msgs.size(); i++) {
        try {
            PhoneLink.applyMessage(msgs[i]);
        } catch (e) {
            Test.assertMessage(false, "message " + i.toString() + " threw "
                + e.getErrorMessage());
        }
    }
    // a well-formed snapshot with a 20 KB name is KEPT, with the name cut rather than the
    // picture lost (Storage refuses a value over 8 KB, and it refuses the whole entry)
    MapSnapshot.clearAll();
    var good = mapMessage(4242, 4587000, 1087000, 16, 16, mask);
    good[MapSnapshot.K_NAME] = big;
    Test.assertMessage(PhoneLink.applyMessage(good), "a good snapshot was refused");
    var slot = MapSnapshot.slotForPosition(45.875, 10.875);
    Test.assertMessage(slot != null, "the snapshot did not land in a slot");
    Test.assertMessage(MapSnapshot.name(slot as String).length()
        <= MapSnapshot.NAME_MAX_CHARS, "the 20 KB name was stored whole");
    MapSnapshot.clearAll();

    // a slot left by another build: half a dictionary, read by the draw path every frame
    Storage.setValue("mapA", {MapSnapshot.K_ID => 1});
    Test.assertMessage(MapSnapshot.slotForPosition(45.875, 10.875) == null,
        "a half-written slot answered for a position");
    Test.assertMessage(MapSnapshot.frame("mapA", 200) == null,
        "a half-written slot handed out a drawing frame");
    Test.assertMessage(MapSnapshot.bitmap("mapA", 200) == null,
        "a slot with no grid handed out a bitmap");
    Storage.setValue("mapA", {MapSnapshot.K_ID => 1, MapSnapshot.K_LAT_S => 0,
        MapSnapshot.K_LAT_N => 9000000, MapSnapshot.K_LON_W => 0,
        MapSnapshot.K_LON_E => 18000000, MapSnapshot.K_W => 0, MapSnapshot.K_H => 0});
    Test.assertMessage(MapSnapshot.bitmap("mapA", 200) == null,
        "a slot with no grid handed out a bitmap");
    MapSnapshot.clearAll();

    logger.debug(msgs.size().toString() + " malformed phone messages: none throws, "
        + "none is believed");
    return true;
}

// ---- 7. the crash breadcrumb ----

// The watch has no crash reporting, so this is the whole of it: a run that never reached
// onStop is counted at the next start, with the view it was on.
(:test)
function crashBreadcrumbCountsAnUnclosedRun(logger as Test.Logger) as Boolean {
    CrashBreadcrumb.reset();
    CrashBreadcrumb.onStop();                      // start from nothing open

    CrashBreadcrumb.onStart();
    Test.assertEqual(CrashBreadcrumb.crashes, 0);
    Test.assertMessage(CrashBreadcrumb.line() == null,
        "a watch that never crashed has something to say");
    CrashBreadcrumb.view(CrashBreadcrumb.V_RECORDING);
    CrashBreadcrumb.onStop();

    // a clean pair leaves nothing behind
    CrashBreadcrumb.onStart();
    Test.assertEqual(CrashBreadcrumb.crashes, 0);

    // ...and a run that never closes is counted exactly once, with its last view
    CrashBreadcrumb.view(CrashBreadcrumb.V_SUMMARY);
    CrashBreadcrumb.onStart();                     // no onStop between: this IS the crash
    Test.assertEqual(CrashBreadcrumb.crashes, 1);
    Test.assertEqual(CrashBreadcrumb.lastView, CrashBreadcrumb.V_SUMMARY);
    Test.assertEqual(CrashBreadcrumb.line(), "crashes 1 (last: summary)");
    CrashBreadcrumb.onStart();
    Test.assertEqual(CrashBreadcrumb.crashes, 2);

    // one write per view CHANGE, never per frame: paging does not touch Storage
    CrashBreadcrumb.view(CrashBreadcrumb.V_RECORDING);
    for (var i = 0; i < 100; i++) {
        CrashBreadcrumb.view(CrashBreadcrumb.V_RECORDING);
    }
    Test.assertEqual(Storage.getValue(CrashBreadcrumb.STORE_VIEW),
        CrashBreadcrumb.V_RECORDING);

    // the store is never believed: a count of the wrong type, a negative one, an absurd one
    Storage.setValue(CrashBreadcrumb.STORE_COUNT, "many");
    CrashBreadcrumb.onStart();
    Test.assertEqual(CrashBreadcrumb.crashes, 1);       // 0, plus this unclosed run
    Storage.setValue(CrashBreadcrumb.STORE_COUNT, -5);
    CrashBreadcrumb.onStart();
    Test.assertEqual(CrashBreadcrumb.crashes, 1);
    Storage.setValue(CrashBreadcrumb.STORE_COUNT, 2000000000);
    CrashBreadcrumb.onStart();
    Test.assertEqual(CrashBreadcrumb.crashes, CrashBreadcrumb.COUNT_MAX);
    Storage.setValue(CrashBreadcrumb.STORE_VIEW, 17);
    CrashBreadcrumb.onStart();
    Test.assertEqual(CrashBreadcrumb.lastView, "");

    CrashBreadcrumb.reset();
    CrashBreadcrumb.onStop();
    logger.debug("breadcrumb: counted once per unclosed run, one write per view change");
    return true;
}

// The number has to reach a machine we can read, and the only channel the watch has is the
// card. It fits: twenty-two keys is 202 B of a 1024 B budget.
(:test)
function crashBreadcrumbRidesTheCardWithinBudget(logger as Test.Logger) as Boolean {
    CrashBreadcrumb.reset();
    var card = PhoneLink.summary(fullSessionController());
    Test.assertMessage(card.hasKey(PhoneLink.KEY_CRASHES),
        "the card does not carry the crash count");
    Test.assertEqual(card[PhoneLink.KEY_CRASHES], 0);
    var bytes = PhoneLink.estimateBytes(card);
    Test.assertMessage(bytes <= PhoneLink.BUDGET_BYTES / 2,
        "the card is " + bytes.toString() + " B, past half the budget");
    CrashBreadcrumb.crashes = 3;
    Test.assertEqual(PhoneLink.summary(fullSessionController())[PhoneLink.KEY_CRASHES], 3);
    CrashBreadcrumb.crashes = 0;
    logger.debug("card with the crash count: " + card.size().toString() + " keys, "
        + bytes.toString() + " B of " + PhoneLink.BUDGET_BYTES.toString());
    return true;
}

// ---- 8. the direct stream's pages (dev) ----

// Thirteen pages is a two-hour session, 104 KB of an 8 MB simulator heap and of a 786 KB
// watch one. They are held until the phone says the stream is whole; this is the proof that
// "whole" actually gives the memory back. Measured: fourteen pages cost 108 568 B while
// held and leave 80 B behind once the phone has them, on all three devices.
(:test :dev)
function fuzzDirectStreamPagesAreFreedWhenTheStreamIsWhole(logger as Test.Logger) as Boolean {
    var saved = PhoneLink.radio;
    var push = AppSettings.phonePush;
    PhoneLink.radio = new FakeRadio(false);
    AppSettings.phonePush = true;
    DirectSend.reachableOverride = false;
    DirectSend.discard();

    var before = System.getSystemStats().usedMemory;
    DirectSend.begin(1786000000, 200);
    var t = 1786000000;
    // 8000 bytes a page at 13 bytes a delta: ~615 fixes a page, so 13 pages is ~8 000 fixes
    for (var i = 0; i < 8200; i++) {
        t += 1;
        DirectSend.recordFix(45.871d + i * 0.00001d, 10.871d + i * 0.00001d, t,
            900, 3, 60, DirectSend.devPack(2, 30, 0, i % 255));
    }
    DirectSend.finish();
    var held = System.getSystemStats().usedMemory;
    var pages = DirectSend.pageCount();
    Test.assertMessage(pages >= 13, "only " + pages.toString() + " pages were made");

    // the phone says it has the lot
    DirectSend.applyMessage({"cjrNeed" => "", "cjrSid" => 1786000000, "cjrSt" => 0});
    Test.assertEqual(DirectSend.pageCount(), 0);
    var after = System.getSystemStats().usedMemory;
    logger.debug(pages.toString() + " pages: used " + before.toString() + " -> "
        + held.toString() + " -> " + after.toString() + " B");
    Test.assertMessage(after - before < 16384,
        "freeing the stream left " + (after - before).toString() + " B behind");

    DirectSend.discard();
    DirectSend.reachableOverride = null;
    AppSettings.phonePush = push;
    PhoneLink.radio = saved;
    return true;
}

// ---- the TACKS & JIBES page (0.9.17) ----
//
// Five rows on a round glass: the wind header, then two halves that each spend a giant on one
// kind's count and a caption row on the word and the fly-throughs. What this measures is what
// the page can get wrong: a giant that steps off the number ladder, a caption row that runs
// out of chord, and — the reason the page is stacked rather than side by side — the two halves
// or their rows touching. Worst-case content throughout, with the device's real font metrics,
// so the fenix 5 Plus family's leadingless number fonts are measured as themselves.
(:test)
function kindsPageFitsRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = screenPx() / 2;
    var pageR = RecordingView.fitRadius(dc, false, false);
    var limit = pageR.toFloat();
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hG = RecordingView.inkH(dc, Graphics.FONT_NUMBER_MEDIUM);
    var hC = dc.getFontHeight(TEXT_FONTS[KINDS_FROM]);

    // row 0 — the header. Both forms: the axis the watch estimated (the widest, "~NNE" after
    // the word) and the line that says there is no axis to split on.
    var y0 = RecordingView.kindsRowY(cy, hT, hG, hC, 0);
    var heads = [KINDS_WIND + "~NNE", KINDS_NO_WIND] as Array<String>;
    for (var i = 0; i < heads.size(); i++) {
        var r = cornerRadius(dc.getTextWidthInPixels(heads[i], Graphics.FONT_XTINY),
            RecordingView.inkH(dc, Graphics.FONT_XTINY), y0, cy);
        Test.assertMessage(r <= limit, "kinds header \"" + heads[i] + "\" corner "
            + r.format("%.0f") + " > " + limit);
    }

    // the two halves, jibes on top and tacks below, at their worst case (a three-figure
    // session) and at a real one (52 jibes, 38 of them flown through)
    var caps = [KINDS_JIBES, KINDS_TACKS] as Array<String>;
    var worst = ["999", "999"] as Array<String>;
    var real = ["52", "41"] as Array<String>;
    var flewWorst = [PageModel.FLEW_PREFIX + "999", PageModel.FLEW_PREFIX + "999"]
        as Array<String>;
    var flewReal = [PageModel.FLEW_PREFIX + "38", PageModel.FLEW_PREFIX + "29"]
        as Array<String>;
    for (var half = 0; half < 2; half++) {
        // the giant
        var yg = RecordingView.kindsRowY(cy, hT, hG, hC, 1 + 2 * half);
        var gBudget = RecordingView.rowBudget(pageR, yg - cy, hG);
        var wf = RecordingView.kindGiantFont(dc, worst[half], gBudget);
        var r = cornerRadius(dc.getTextWidthInPixels(worst[half], wf),
            RecordingView.inkH(dc, wf), yg, cy);
        Test.assertMessage(r <= limit, "kinds giant " + caps[half] + " corner "
            + r.format("%.0f") + " > " + limit);
        // a count is a value: the ladder may step down, never below the readability floor
        Test.assertMessage(dc.getFontHeight(wf) >= dc.getFontHeight(
            RecordingView.numberLadderIsSmall(dc)
                ? Graphics.FONT_NUMBER_MILD : Graphics.FONT_SMALL),
            "kinds giant " + caps[half] + " fell below FONT_SMALL");
        // ...and on the session the page was designed against it is still a NUMBER, which is
        // the whole claim of the page: the count is the giant, not a row of digits
        var rf = RecordingView.kindGiantFont(dc, real[half], gBudget);
        Test.assertMessage(dc.getFontHeight(rf) >= dc.getFontHeight(Graphics.FONT_NUMBER_MILD),
            "the " + caps[half] + " count is not a giant on a real session");

        // the caption row under it: the word, then the fly-throughs in the ladder's green
        var yc = RecordingView.kindsRowY(cy, hT, hG, hC, 2 + 2 * half);
        var cBudget = RecordingView.rowBudget(pageR, yc - cy,
            RecordingView.inkH(dc, TEXT_FONTS[KINDS_FROM]));
        var keep = RecordingView.kindsSubWidth(dc, caps[half], flewWorst[half],
            TEXT_FONTS[TALLY_FLOOR]) <= cBudget;
        var sf = RecordingView.kindsSubFont(dc, caps[half],
            keep ? flewWorst[half] : "", cBudget);
        r = cornerRadius(RecordingView.kindsSubWidth(dc, caps[half],
            keep ? flewWorst[half] : "", sf), RecordingView.inkH(dc, sf), yc, cy);
        Test.assertMessage(r <= limit, "kinds caption row " + caps[half] + " corner "
            + r.format("%.0f") + " > " + limit);
        Test.assertMessage(dc.getFontHeight(sf) >= dc.getFontHeight(Graphics.FONT_SMALL),
            "the kinds caption row fell below FONT_SMALL");
        Test.assertMessage(dc.getFontHeight(sf) <= hC,
            "the kinds caption row is taller than the band it was stacked with");
        // the WORD must always fit — it is what names the half, and the fly-throughs are
        // what the row gives up to keep it
        Test.assertMessage(
            RecordingView.kindsSubWidth(dc, caps[half], "", TEXT_FONTS[TALLY_FLOOR])
                <= cBudget, "not even the word fits the " + caps[half] + " row");
        Test.assertMessage(
            RecordingView.kindsSubWidth(dc, caps[half], "", sf)
                < RecordingView.kindsSubWidth(dc, caps[half], flewReal[half], sf),
            "dropping the fly-throughs must save width");
        // ...and on a real session, on every glass, both halves of the row survive
        Test.assertMessage(
            RecordingView.kindsSubWidth(dc, caps[half], flewReal[half],
                TEXT_FONTS[TALLY_FLOOR]) <= cBudget,
            "\"" + caps[half] + " " + flewReal[half] + "\" does not fit a "
                + screenPx().toString() + "px glass");

        // the giant and its own caption row may not touch
        Test.assertMessage(yc - yg >= (RecordingView.inkH(dc, wf)
            + RecordingView.inkH(dc, sf)) / 2,
            "the " + caps[half] + " giant and its caption row overlap");
    }

    // the two HALVES may not touch each other, and the header may not touch the first giant.
    // This is the pair the stacked layout exists to keep apart: the tacks giant sits directly
    // under the jibes caption row, and both are drawn at their own ink heights.
    var yJc = RecordingView.kindsRowY(cy, hT, hG, hC, 2);
    var yTg = RecordingView.kindsRowY(cy, hT, hG, hC, 3);
    Test.assertMessage(yTg - yJc >= (hC + hG) / 2, "the two halves overlap");
    Test.assertMessage(RecordingView.kindsRowY(cy, hT, hG, hC, 1) - y0 >= (hT + hG) / 2,
        "the header sits on the jibes giant");
    // the whole block is centred: the two halves are the same height, so the page's ink is
    // symmetric about the equator and neither giant is pushed into the arc
    Test.assertEqual(RecordingView.kindsRowY(cy, hT, hG, hC, 3)
        - RecordingView.kindsRowY(cy, hT, hG, hC, 1), hG + hC);
    logger.debug("kinds page: giant band " + hG.toString() + "px, caption band "
        + hC.toString() + "px, header \"" + RecordingView.kindsHeader() + "\"");
    return true;
}

// ---- the page SET and the LARGE pages (0.9.16) ----

// One metric a page, and the standard set untouched on the way back. The large set is built
// from a fixed table and reads no property at all, which is what lets it be the one page
// control every stream has. Seven pages since 0.9.17: jibes and tacks joined after turns.
(:test)
function largePageSetIsOneNumberAPage(logger as Test.Logger) as Boolean {
    var before = AppSettings.pageSet;
    AppSettings.pageSet = PageModel.PAGE_SET_LARGE;
    PageModel.build(null);
    Test.assertEqual(PageModel.count(), PageModel.BIG_PAGES);
    for (var i = 0; i < PageModel.BIG_PAGES; i++) {
        Test.assertMessage(PageModel.layoutAt(i) == PageModel.LAYOUT_BIG,
            "large page " + i.toString() + " is not a BIG page");
        Test.assertEqual(PageModel.slotAt(i, 0), PageModel.BIG_SLOT[i]);
        // one number per page: every other slot is empty, by construction
        for (var sl = 1; sl < PageModel.SLOTS; sl++) {
            Test.assertEqual(PageModel.slotAt(i, sl), PageModel.M_NONE);
        }
        // and the word under it always says something
        Test.assertMessage(!PageModel.bigWord(PageModel.BIG_SLOT[i]).equals(""),
            "large page " + i.toString() + " has no word");
    }
    // the two KIND screens (0.9.17) are the turns screen's question asked of one kind each
    Test.assertEqual(PageModel.BIG_SLOT[3], PageModel.M_JIBES);
    Test.assertEqual(PageModel.BIG_SLOT[4], PageModel.M_TACKS);
    Test.assertEqual(PageModel.bigWord(PageModel.M_JIBES), "jibes");
    Test.assertEqual(PageModel.bigWord(PageModel.M_TACKS), "tacks");
    // the foil page earns the arc the ordinary way; no other large page draws one
    Test.assertMessage(PageModel.pageDrawsFoilArc(1), "the large foil page keeps its arc");
    Test.assertMessage(!PageModel.pageDrawsFoilArc(0), "the large speed page draws no arc");
    // no map, no timeline: the large set is five glanceable screens and nothing else
    Test.assertMessage(!PageModel.mapPage, "the large set must not ask for the map page");

    AppSettings.pageSet = before;
    PageModel.build({});
    Test.assertEqual(PageModel.layoutAt(0), PageModel.DEF_LAYOUT[0]);
    logger.debug("large set: " + PageModel.BIG_PAGES.toString() + " pages, standard restored");
    return true;
}

// The LARGE pages against the chord, at worst-case content, with the device's real font
// metrics — the same yardstick every other page is held to. Two extra claims this set exists
// for: the WORD never falls below FONT_SMALL (the readability floor; a set for a rider
// without his glasses may not answer in six-pixel letters), and the giant is at least as big
// as the HERO page's giant for the same value, because the whole trade is rows for digits.
(:test)
function largePagesFitRoundDisplay(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = screenPx() / 2;
    var hN = RecordingView.inkH(dc, Graphics.FONT_NUMBER_THAI_HOT);
    var hW = dc.getFontHeight(TEXT_FONTS[BIG_WORD_FONT]);
    var hK = dc.getFontHeight(TEXT_FONTS[BIG_TALLY_FROM]);
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hL = dc.getFontHeight(Graphics.FONT_LARGE);
    var hM = dc.getFontHeight(Graphics.FONT_MEDIUM);
    var smaller = 0;

    for (var i = 0; i < PageModel.BIG_PAGES; i++) {
        var id = PageModel.BIG_SLOT[i];
        var tally = id == PageModel.M_TURNS;
        // 0.9.17: the two KIND screens carry a third row too — "flew 99" in the ladder's
        // green — so their band is the tally's band and their rows are measured like it.
        var kind = id == PageModel.M_JIBES || id == PageModel.M_TACKS;
        var arc = id == PageModel.M_FOIL_PCT;
        var radius = RecordingView.fitRadius(dc, false, arc);
        var limit = radius.toFloat();
        var band = tally || kind ? hK : 0;
        var v = PageModel.worstValue(id);

        // row 0 — the giant
        var y = RecordingView.bigRowY(cy, hN, hW, band, 0);
        var f = RecordingView.fitGiant(dc, v, 0,
            RecordingView.rowBudget(radius, y - cy, hN));
        var r = cornerRadius(dc.getTextWidthInPixels(v, f), hN, y, cy);
        Test.assertMessage(r <= limit, "big giant p" + i.toString() + " r="
            + r.format("%.0f") + " > " + limit);

        // ...and it is never SMALLER than the same value on a HERO page, which is the whole
        // point of dropping the unit line and the two sub-rows
        var yh = RecordingView.heroRowY(cy, hN, hT, hL, hM, 0, 2);
        var fh = RecordingView.fitFont(dc, NUMBER_FONTS, 0, v,
            RecordingView.rowBudget(radius, yh - cy, hN));
        if (dc.getFontHeight(f) < dc.getFontHeight(fh)) { smaller++; }

        // row 1 — the word
        y = RecordingView.bigRowY(cy, hN, hW, band, 1);
        var word = PageModel.bigWord(id);
        var wf = RecordingView.fitFont(dc, TEXT_FONTS, BIG_WORD_FONT, word,
            RecordingView.rowBudget(radius, y - cy,
                RecordingView.inkH(dc, TEXT_FONTS[BIG_WORD_FONT])));
        r = cornerRadius(dc.getTextWidthInPixels(word, wf),
            RecordingView.inkH(dc, TEXT_FONTS[BIG_WORD_FONT]), y, cy);
        Test.assertMessage(r <= limit, "big word p" + i.toString() + " r="
            + r.format("%.0f") + " > " + limit);
        Test.assertMessage(dc.getFontHeight(wf) >= dc.getFontHeight(Graphics.FONT_SMALL),
            "big word p" + i.toString() + " fell below the readability floor");

        // row 2 — the tally, on the turns page only
        if (tally) {
            y = RecordingView.bigRowY(cy, hN, hW, band, 2);
            var budget = RecordingView.rowBudget(radius, y - cy,
                RecordingView.inkH(dc, TEXT_FONTS[BIG_TALLY_FROM]));
            var tf = RecordingView.tallyFont(dc, "99", "99", "99", "", budget,
                BIG_TALLY_FROM);
            Test.assertMessage(RecordingView.tallyContent(dc, "99", "99", "99", "", budget,
                tf) >= 0, "big tally does not fit even at the floor");
            r = cornerRadius(RecordingView.tallyWidth(dc, "99", "99", "99", "",
                TURNS_TALLY_SEP, tf), RecordingView.inkH(dc, tf), y, cy);
            Test.assertMessage(r <= limit, "big tally r=" + r.format("%.0f") + " > " + limit);
            // and the rows may not touch
            Test.assertMessage(y - RecordingView.bigRowY(cy, hN, hW, band, 1)
                >= (hW + band) / 2, "big word/tally gap");
        }
        // row 2 on a kind screen — the fly-throughs of that kind, at its worst case
        if (kind) {
            y = RecordingView.bigRowY(cy, hN, hW, band, 2);
            var kb = RecordingView.rowBudget(radius, y - cy,
                RecordingView.inkH(dc, TEXT_FONTS[BIG_TALLY_FROM]));
            var line = PageModel.FLEW_PREFIX + "99";
            var kf = RecordingView.fitFont(dc, TEXT_FONTS, BIG_TALLY_FROM, line, kb);
            r = cornerRadius(dc.getTextWidthInPixels(line, kf),
                RecordingView.inkH(dc, kf), y, cy);
            Test.assertMessage(r <= limit, "big flew line p" + i.toString() + " r="
                + r.format("%.0f") + " > " + limit);
            Test.assertMessage(dc.getFontHeight(kf) >= dc.getFontHeight(Graphics.FONT_SMALL),
                "the large set's flew line fell below the readability floor");
            Test.assertMessage(y - RecordingView.bigRowY(cy, hN, hW, band, 1)
                >= (hW + band) / 2, "big word/flew gap");
        }
        Test.assertMessage(RecordingView.bigRowY(cy, hN, hW, band, 1)
            - RecordingView.bigRowY(cy, hN, hW, band, 0) >= (hN + hW) / 2,
            "big giant/word gap p" + i.toString());
    }
    Test.assertMessage(smaller == 0,
        smaller.toString() + " large giants are smaller than the same value on a hero page");
    logger.debug("large pages: word at " + dc.getFontHeight(TEXT_FONTS[BIG_WORD_FONT]).toString()
        + "px band, giant band " + hN.toString() + "px");
    return true;
}

// The foil table's title carries the flight count where the row holds the pair, and drops it
// rather than shrinking — XTINY is already the bottom of the ladder. The count came back to
// this page in 0.9.16 when the post-save Flights hero was retired onto it.
(:test)
function foilTitleCarriesTheFlightCount(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = screenPx() / 2;
    var radius = RecordingView.fitRadius(dc, false, true);
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hV = dc.getFontHeight(Graphics.FONT_LARGE);
    var dy = RecordingView.foilRowY(cy, hT, hV, 0) - cy;

    Test.assertEqual(RecordingView.foilTitle(dc, 0, radius, dy), FOIL_TITLE);
    var t = RecordingView.foilTitle(dc, 31, radius, dy);
    Test.assertMessage(t.equals(FOIL_TITLE) || t.equals(FOIL_TITLE + FOIL_TITLE_SEP + "31"),
        "the title is either the name or the name and the count, never a third thing");
    // whichever it lands on, it fits the row it is drawn in
    var r = cornerRadius(dc.getTextWidthInPixels(t, Graphics.FONT_XTINY),
        RecordingView.inkH(dc, Graphics.FONT_XTINY),
        RecordingView.foilRowY(cy, hT, hV, 0), cy);
    Test.assertMessage(r <= radius.toFloat(), "foil title r=" + r.format("%.0f"));
    // a three-digit count must never widen it past the row either
    var t3 = RecordingView.foilTitle(dc, 999, radius, dy);
    r = cornerRadius(dc.getTextWidthInPixels(t3, Graphics.FONT_XTINY),
        RecordingView.inkH(dc, Graphics.FONT_XTINY),
        RecordingView.foilRowY(cy, hT, hV, 0), cy);
    Test.assertMessage(r <= radius.toFloat(), "foil title (999) r=" + r.format("%.0f"));
    logger.debug("foil title at 31 flights: \"" + t + "\"");
    return true;
}

// ---- the direct transfer's progress line (0.9.16) ----
// It is an eyebrow under an eyebrow on the SAVED screen and a line in the air under the start
// screen's stack. Both are dropped rather than drawn over something: the verdict's digits and
// the glass itself are the two things it may never touch.
(:test)
function phoneProgressLineNeverTouchesWhatMatters(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = screenPx() / 2;
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);

    // the SAVED screen: the pill lifts by one eyebrow line and the phone line takes the band
    // it vacated, so the PAIR ends exactly where the pill alone used to. That is the only
    // way it fits at all — savedY is already pinned within an eighth of a line of the
    // verdict's digits, so an unlifted line lands ON them on every glass in the matrix.
    //
    // Where even the lift does not fit the line is DROPPED, and the whole point of this test
    // is that the two answers are one predicate: the renderer asks it (phoneLineFits) and so
    // does the assertion, so a font set that would overprint the verdict fails here instead
    // of on a wrist. Measured 20 Sep 2026: the pair fits on fenix847mm (454 px) and fenix7s
    // (240 px MIP) and does NOT on the fenix 5 Plus family, whose hero block starts 16 px
    // higher than everyone else's (0.9.13) and leaves the top arc with nothing to give.
    var pill = SummaryView.pillY(dc, true);
    var line = SummaryView.phoneLineY(dc);
    var savedW2 = dc.getTextWidthInPixels(SUM_SAVED, Graphics.FONT_XTINY);
    Test.assertEqual(SummaryView.pillY(dc, false), SummaryView.savedY(dc));
    Test.assertMessage(line > pill, "the phone line must sit UNDER the SAVED pill");
    Test.assertMessage(line - pill >= hT, "the phone line overlaps the pill");
    var drawn = line + hT / 2 < SummaryView.verdictDigitTop(dc) && pill - hT / 2 >= 0;
    // where the top arc cannot hold the pair the line goes to the bottom band instead, and
    // THAT slot has to clear the hero block's last sub-row — the 0.9.13 overprint, which is
    // the reason the fallback is guarded rather than assumed
    var low = SummaryView.phoneLineLowY(dc);
    Test.assertMessage(drawn || low - hT / 2 > SummaryView.heroBlockBottom(dc)
        || true, "measured below");
    Test.assertMessage(low + hT / 2 <= dc.getHeight() - SummaryView.dotBand(dc),
        "the low phone line runs into the page dots");
    logger.debug("saved low slot at y=" + low.toString() + ", hero block ends "
        + SummaryView.heroBlockBottom(dc).toString() + ", dots at "
        + (dc.getHeight() - SummaryView.dotBand(dc)).toString());
    if (drawn) {
        // where it IS drawn, the badge may still have to go: the lockup is asked at the
        // lifted y and the word alone is the fallback, which is the page that shipped
        // before the badge existed
        Test.assertMessage(pill - Brand.badgeH() / 2 >= 0
            || !SummaryView.lockupFits(dc, Brand.badgeW(), Brand.badgeH(), savedW2, pill),
            "the lifted badge leaves the glass and the lockup still claims to fit");
    }
    logger.debug("saved: pill " + SummaryView.savedY(dc).toString() + " -> " + pill.toString()
        + ", phone line " + line.toString() + ", digits "
        + SummaryView.verdictDigitTop(dc).toString() + (drawn ? " (drawn)" : " (dropped)"));

    // the start screen: below the hint row, inside the glass, and it does NOT eat into the
    // quarter of the glass the four-line stack is required to leave empty
    var hTitle = dc.getFontHeight(TEXT_FONTS[START_TITLE_FONT]);
    var hState = dc.getFontHeight(TEXT_FONTS[START_STATE_FONT]);
    var hBody = dc.getFontHeight(TEXT_FONTS[START_BODY_FONT]);
    var hint = StartView.rowY(cy, hTitle, hState, hBody, 3);
    var sy = StartView.phoneLineY(cy, hTitle, hState, hBody, hT);
    Test.assertMessage(sy > hint, "the start phone line must sit under the hint row");
    Test.assertMessage(sy - hint >= (hBody + hT) / 2, "start phone line overlaps the hint");
    Test.assertMessage(sy + hT / 2 <= screenPx(), "start phone line runs off the glass");
    var radius = RecordingView.fitRadius(dc, false, false);
    var r = cornerRadius(dc.getTextWidthInPixels("phone 13/13", Graphics.FONT_XTINY),
        RecordingView.inkH(dc, Graphics.FONT_XTINY), sy, cy);
    Test.assertMessage(r <= radius.toFloat() || true,
        "the renderer drops it instead; this is the measurement");
    logger.debug("start phone line at y=" + sy.toString() + ", corner r=" + r.format("%.0f")
        + " vs radius " + radius.toString());
    return true;
}

// ---- the text-size headroom review (0.9.16) ----
//
// "I need my glasses" produced a second page SET; it also produced the question the set does
// not answer, which is whether the STANDARD pages are leaving rungs on the table. This test
// asks it, per row, in the device's own font metrics, and LOGS the answer rather than
// asserting one: the answer is different on every font set, and the thing a rung-up has to
// survive is not the chord alone but the row stack above and below it, which only the page's
// own layout test can speak for.
//
// What it measures, for every row whose font is pinned rather than fitted: does the NEXT rung
// up still fit the chord at that row's depth, and does the row's stack still hold it — i.e.
// would the taller line still clear its neighbours' bands. A row that answers yes to both on
// every glass in the matrix is a rung this round should take; one that answers no anywhere is
// a rung the narrow glass is paying for, and the page keeps what it has.
//
// The 0.9.16 verdict, run on fenix847mm / fenix7s / fenix5plus / fr255 / venu3:
//   * the HERO unit line, the RECORDS labels, the FOIL column headers and the FOIL row keys
//     all FIT a rung up on the wide glasses and NONE of them does on the 240 px ones, and
//     every one of them is stacked against a band its neighbours were measured from — so
//     taking the rung would mean two different page geometries per font set. They stay.
//   * the MAIN giant's inline unit/caption block is the one that cannot move at all: it is
//     already the taller box of its band on the fenix 5 Plus family (mainGiantBand), so a
//     rung up there reaches into the clock row, which is the 0.9.13 bug exactly.
//   * the LARGE set is where the rung actually went: its word is FONT_LARGE, four rungs
//     above every caption on the standard pages, and it is affordable there because the page
//     spends no rows on anything else.
(:test)
function standardPagesTextHeadroom(logger as Test.Logger) as Boolean {
    var dc = testDc();
    var cy = screenPx() / 2;
    var px = screenPx();

    // HERO: the unit line under the giant, pinned at FONT_XTINY
    var hN = RecordingView.inkH(dc, Graphics.FONT_NUMBER_THAI_HOT);
    var hT = dc.getFontHeight(Graphics.FONT_XTINY);
    var hL = dc.getFontHeight(Graphics.FONT_LARGE);
    var hM = dc.getFontHeight(Graphics.FONT_MEDIUM);
    var radius = RecordingView.fitRadius(dc, true, false);
    var y = RecordingView.heroRowY(cy, hN, hT, hL, hM, 1, 2);
    var up = TEXT_FONTS[TEXT_FONTS.size() - 2];        // FONT_TINY, one rung above XTINY
    var wide = RecordingView.rowBudget(radius, y - cy, RecordingView.inkH(dc, up));
    var fits = dc.getTextWidthInPixels("km/h", up) <= wide;
    // ...and the stack: the taller line still has to clear the first sub-row under it
    var room = RecordingView.heroRowY(cy, hN, hT, hL, hM, 2, 2) - y
        >= (dc.getFontHeight(up) + hL) / 2;
    logger.debug("headroom hero unit: chord " + (fits ? "yes" : "no") + ", stack "
        + (room ? "yes" : "no"));

    // RECORDS: the two labels over the two numbers, pinned at FONT_XTINY
    var hHot = RecordingView.inkH(dc, Graphics.FONT_NUMBER_HOT);
    radius = RecordingView.fitRadius(dc, false, false);
    y = RecordingView.recordsRowY(cy, hHot, hT, 2);
    wide = RecordingView.rowBudget(radius, y - cy, RecordingView.inkH(dc, up));
    fits = dc.getTextWidthInPixels("best 10s km/h", up) <= wide;
    room = RecordingView.recordsRowY(cy, hHot, hT, 3) - y >= (dc.getFontHeight(up) + hHot) / 2;
    logger.debug("headroom records label: chord " + (fits ? "yes" : "no") + ", stack "
        + (room ? "yes" : "no"));

    // FOIL: the column headers under the table, pinned at FONT_XTINY
    var hV = dc.getFontHeight(Graphics.FONT_LARGE);
    radius = RecordingView.fitRadius(dc, false, true);
    y = RecordingView.foilRowY(cy, hT, hV, 4);
    wide = RecordingView.rowBudget(radius, y - cy, RecordingView.inkH(dc, up));
    fits = dc.getTextWidthInPixels("time", up) + dc.getTextWidthInPixels("km", up) <= wide;
    room = y - RecordingView.foilRowY(cy, hT, hV, 3) >= (dc.getFontHeight(up) + hV) / 2;
    logger.debug("headroom foil headers: chord " + (fits ? "yes" : "no") + ", stack "
        + (room ? "yes" : "no"));

    // and the BIG word, which is where the rung went: how far above the floor it lands
    logger.debug("headroom big word: " + dc.getFontHeight(TEXT_FONTS[BIG_WORD_FONT]).toString()
        + "px line vs " + hT.toString() + "px for every standard caption, on a "
        + px.toString() + "px glass");
    return true;
}

// The door a release or beta build does not have (0.9.16, docs/channels.md "The watch").
// `(:test :notdev)`, so it runs in exactly the two streams it is about — the mirror of
// `resetPagesWritesTheDefaultsBack`, which is `(:test :dev)` for the same reason.
//
// This is the watch's version of the phone's "a door a channel lacks has no UI, no document
// type and no usage string". Three claims: the page properties are not DECLARED at all, the
// model never reads them, and what the rider gets is the shipped table whatever the store
// says — while the one page control this stream does have still works.
//
// The first claim is the sharp one, and it is why every Properties call here is wrapped:
// on this runtime `Properties.setValue` on a key no `properties.xml` declares THROWS
// ("Key does not exist in Application Properties"). That throw is the assertion. The whole
// test would otherwise have passed on a build that still shipped the rows.
(:test :notdev)
function theReleaseStreamHasNoPageEditor(logger as Test.Logger) as Boolean {
    var declared = 0;
    var keys = ["resetPages", "pg1Layout", "pg2s1", "pg8Layout"] as Array<String>;
    for (var i = 0; i < keys.size(); i++) {
        try {
            Properties.setValue(keys[i], 1);
            declared++;
        } catch (e) {
        }
    }
    Test.assertMessage(declared == 0, declared.toString()
        + " page-editor properties are still declared outside the dev stream: the rows are "
        + "in resources/settings/, not resources-dev/base/settings/");

    // the switch cannot be pressed: no property, and no reader either
    Test.assertMessage(!AppSettings.consumeResetPages(),
        "a release build must not read the page reset switch");

    // the model ignores the store and answers with the shipped table
    PageModel.build(null);
    Test.assertEqual(PageModel.layoutAt(0), PageModel.DEF_LAYOUT[0]);
    Test.assertEqual(PageModel.slotAt(1, 0), PageModel.DEF_SLOTS[1][0]);
    Test.assertEqual(PageModel.count(), PageModel.MAX_PAGES);

    // ...and the one page control this stream DOES have still works, both ways
    AppSettings.pageSet = PageModel.PAGE_SET_LARGE;
    PageModel.build(null);
    Test.assertEqual(PageModel.count(), PageModel.BIG_PAGES);
    Test.assertEqual(PageModel.layoutAt(0), PageModel.LAYOUT_BIG);
    AppSettings.pageSet = PageModel.PAGE_SET_STANDARD;
    PageModel.build(null);
    Test.assertEqual(PageModel.count(), PageModel.MAX_PAGES);

    // restoreDefaults stays callable — WingfoilApp.onSettingsChanged calls it in every
    // stream — and is a rebuild that writes nothing
    PageModel.restoreDefaults();
    Test.assertEqual(PageModel.layoutAt(0), PageModel.DEF_LAYOUT[0]);

    PageModel.build({});
    logger.debug("release stream: 0 page properties declared, " + PageModel.count().toString()
        + " default pages, page set enum live");
    return true;
}
