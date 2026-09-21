import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;
import WingFoilCore;

// Post-save review. A CIQ app gets no native post-activity screen, so this is the ONE moment
// between the water and Garmin Connect — and it used to spend that moment on five rows of
// FONT_SMALL stacked at a 32 px pitch against a 53 px line height, i.e. rows whose descenders
// landed in the caps of the row below, with 30 % of the glass empty underneath them and no
// hierarchy at all. Every coordinate was absolute and there was no layout test.
//
// It is now the same shape as the recording screens: pages the rider cycles with UP/DOWN,
// each one a giant number with its unit line and up to two rows under it, all stacked from
// dc.getFontHeight() so a row pitch can never again be smaller than a line. START or BACK
// exits from any page, exactly as before.
//
// WHAT THE ENGINE STILL HAS. SessionController.finishSave() nulls `_session` and stops GPS
// but never touches `engine`, so detector / records / turns / pump / hrCost / history /
// distM / timerS and the breadcrumb are all live and complete here. Nothing on these pages
// is a new measurement; it is the session's own numbers, finally shown.
//
// Two things this screen may NOT do:
//   * reuse the firmware's map. MapTrackView keeps itself centred on the CURRENT position and
//     finishSave has already called stopGps(), so paging onto it after a save would show a map
//     centred on nothing — and on the fenix 8 it killed the app outright, which is why 0.9.2
//     dropped it from the live page too. The track is drawn with Dc primitives from the
//     lat/lon buffer (TrackDraw), which WingfoilApp fills unconditionally for exactly this.
//   * assume every page exists. Turns, takeoffs and the track are conditional, so the page
//     LIST is built per session and the dots at the bottom count what is really there.
module SummaryNav {
    var index as Number = 0;

    // Page ids, in display order.
    enum {
        S_VERDICT = 0,
        S_SPEED = 1,
        // S2 was a bespoke speed hero until 0.9.18; it is the live RECORDS page now
        // (SummaryView.drawRecords). The id keeps its name — it is the page's identity, and
        // renaming an enum value that is stored nowhere buys nothing.
        // S3 was the bespoke "Flights" hero until 0.9.16; it is the live foil table now
        // (SummaryView.drawFoil), which carries the same three numbers and three more.
        S_FOIL = 2,
        S_TURNS = 3,
        S_TAKEOFFS = 4,
        S_STORY = 5,
        S_TRACK = 6,
        // 0.9.17, appended rather than inserted: these ids are a page's NAME, and the order
        // is the `_pages` list below. Tacks & jibes shows after Turns there, exactly where it
        // shows on the water.
        S_KINDS = 7
    }

    var _pages as Array<Number> = [S_VERDICT];

    // Which pages this session earned. Verdict/speed/foil/story always; turns only with a
    // turn to talk about, takeoffs only when the accelerometer was on and something happened,
    // the track only with a line to draw. A page that would say "0" is not a page.
    // Since 0.9.18 a page also has to be SWITCHED ON. The after-save review is the live pages
    // (six of the eight are their live twins drawn by the same code), so it follows the same
    // seven switches rather than carrying a second set nobody would think to look for: hide
    // the Story page and it is gone from the water AND from the review.
    //
    // S1 SAVED has no switch — it is the acknowledgement the rider pressed for, and it is
    // what the page-position dots count from. S6 Takeoffs follows FOIL: it is the only
    // after-save page with no live twin to inherit from, and what it counts is how often he
    // got onto the foil.
    function build(c as SessionController) as Void {
        var e = c.engine;
        var p = [S_VERDICT] as Array<Number>;
        if (PageModel.shown(PageModel.SHOW_RECORDS)) {
            p.add(S_SPEED);
        }
        if (PageModel.shown(PageModel.SHOW_FOIL)) {
            p.add(S_FOIL);
        }
        if (e.turns.turnCount > 0 && PageModel.shown(PageModel.SHOW_TURNS)) {
            p.add(S_TURNS);
        }
        // The kinds page needs a KIND to show. Without a wind axis every turn is a generic
        // turn and both counts are 0, and a page that would say 0 is not a page — the same
        // rule the takeoffs and track pages are gated by. The live page stays in the cycle
        // either way, because on the water the axis can still arrive.
        if ((e.turns.tackCount > 0 || e.turns.jibeCount > 0)
                && PageModel.shown(PageModel.SHOW_KINDS)) {
            p.add(S_KINDS);
        }
        if ((e.pump.attempts() > 0 || e.pump.strokes > 0)
                && PageModel.shown(PageModel.SHOW_FOIL)) {
            p.add(S_TAKEOFFS);
        }
        if (PageModel.shown(PageModel.SHOW_STORY)) {
            p.add(S_STORY);
        }
        if (e.trackN >= 2 && PageModel.shown(PageModel.SHOW_MAP)) {
            p.add(S_TRACK);
        }
        _pages = p;
        index = 0;
    }

    function count() as Number {
        return _pages.size();
    }

    function pageAt(i as Number) as Number {
        return _pages[wrap(i)];
    }

    function wrap(i as Number) as Number {
        var n = _pages.size();
        var k = i % n;
        return k < 0 ? k + n : k;
    }

    function step(dir as Number) as Void {
        index = wrap(index + dir);
        WatchUi.requestUpdate();
    }
}

// Page-position dots on the bottom arc, and the track renderer's geometry: both are shared
// with the layout test, so they live at file scope beside the constants they use.
const SUM_DOT_GAP = 4;
const SUM_SAVED = "SAVED";
const SUM_NOT_SAVED = "NOT SAVED";
// The track page draws into the square inscribed in the circle, inset by this margin.
//
// It grew from 10 to 34 when the distance caption stopped being FONT_XTINY. That caption is a
// VALUE — "12.4 km" — and the readability floor for a value on this watch is FONT_SMALL, so
// XTINY was the one place in the app where a number was drawn at a label's size. The bigger
// line needs 39 px of ink hanging below the box instead of 28, and the page-position dots on
// the bottom arc do not move, so the box gives up 34 px of its side (306 -> 272 on a 454 px
// glass, 11 %) to buy the number its legibility. A map you can read the scale of beats a map
// 11 % wider whose scale you cannot.
const SUM_TRACK_MARGIN = 34;

// ---- S6 Takeoffs, in words (0.9.18) ----
// Every string on that page, and each of them is a number's NAME rather than its unit. See
// SummaryView.drawTakeoffs for what each number actually is and why the old spelling of it
// ("39/56", "4.3 to foil", "+19 bpm") could not be read off a sheet, and why the two smaller
// facts ended up on two rows rather than on one with a separator between them.
const TAKEOFF_WORD = "takeoffs";
// Spaces INSIDE the word, not around it: the counts either side are drawn in a number font
// and the word at FONT_XTINY, so the two are not on one baseline run and the gaps have to be
// part of the small string. The same trick the streak row's " / " uses.
const TAKEOFF_OF = " of ";
const TAKEOFF_PUMPS = " pumps each";
// "last", because it is ONE takeoff's cost and not the session's average — the number the
// page printed as a bare "+19 bpm" beside an average, which reads as another average.
const TAKEOFF_COST = "last +";
const TAKEOFF_BPM = " bpm";

// Where the direct transfer's status line lands on the verdict page (0.9.16, dev stream).
// See SummaryView.phoneLineSlot for what picks between them.
const PHONE_LINE_NONE = 0;
const PHONE_LINE_TOP = 1;
const PHONE_LINE_LOW = 2;

class SummaryView extends WatchUi.View {

    const CV = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        CrashBreadcrumb.view(CrashBreadcrumb.V_SUMMARY);
    }

    function onUpdate(dc as Dc) as Void {
        var c = getApp().controller;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var page = SummaryNav.pageAt(SummaryNav.index);
        if (page == SummaryNav.S_VERDICT) {
            drawVerdict(dc, c);
        } else if (page == SummaryNav.S_SPEED) {
            drawRecords(dc, c);
        } else if (page == SummaryNav.S_FOIL) {
            drawFoil(dc, c);
        } else if (page == SummaryNav.S_TURNS) {
            drawTurns(dc, c);
        } else if (page == SummaryNav.S_KINDS) {
            drawKinds(dc, c);
        } else if (page == SummaryNav.S_TAKEOFFS) {
            drawTakeoffs(dc, c);
        } else if (page == SummaryNav.S_STORY) {
            drawStory(dc, c);
        } else {
            drawTrack(dc, c);
        }
        drawDots(dc);
    }

    // ---- the hero shape every numeric page uses ----
    // Giant + unit line + up to two rows, on RecordingView's own row stack, so the pitch is a
    // font height by construction and the layout test measures the same geometry the renderer
    // draws. `giantCol` carries the page's meaning where it has one (the verdict's phase teal,
    // the record's effort orange) and is plain white where it does not.
    hidden function drawHero(dc as Dc, giant as String, unit as String, row1 as String,
            row2 as String, giantCol as Number, arc as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = RecordingView.fitRadius(dc, false, arc);
        var hN = RecordingView.inkH(dc, Graphics.FONT_NUMBER_THAI_HOT);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);
        var hM = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var nSub = (row1.equals("") ? 0 : 1) + (row2.equals("") ? 0 : 1);

        var y = RecordingView.heroRowY(cy, hN, hT, hL, hM, 0, nSub);
        dc.setColor(giantCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, RecordingView.fitFont(dc, NUMBER_FONTS, 0, giant,
            RecordingView.rowBudget(radius, y - cy,
                RecordingView.inkH(dc, Graphics.FONT_NUMBER_THAI_HOT))), giant, CV);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, RecordingView.heroRowY(cy, hN, hT, hL, hM, 1, nSub),
            Graphics.FONT_XTINY, unit, CV);
        if (!row1.equals("")) {
            drawRow(dc, cx, cy, radius, RecordingView.heroRowY(cy, hN, hT, hL, hM, 2, nSub),
                0, row1, Graphics.COLOR_WHITE);
        }
        if (!row2.equals("")) {
            drawRow(dc, cx, cy, radius, RecordingView.heroRowY(cy, hN, hT, hL, hM, 3, nSub),
                1, row2, Graphics.COLOR_WHITE);
        }
    }

    hidden function drawRow(dc as Dc, cx as Number, cy as Number, radius as Number,
            y as Number, from as Number, text as String, col as Number) as Void {
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, RecordingView.fitFont(dc, TEXT_FONTS, from, text,
            RecordingView.rowBudget(radius, y - cy, RecordingView.inkH(dc, TEXT_FONTS[from]))),
            text, CV);
    }

    // ---- S1 Verdict: the page the rider lands on ----
    // Foil % is the one number that answers "was that a good session", it is already the
    // giant on recording page 2, and the arc gives it a shape read before the digits are.
    // "SAVED" is an acknowledgement in the corner, not a headline: he pressed save.
    hidden function drawVerdict(dc as Dc, c as SessionController) as Void {
        var e = c.engine;
        _painter.drawFoilBezel(dc, c);
        // Rows stay SHORT on purpose. The chord at the two sub-row depths on a 454 px glass
        // is ~250 px once the arc has taken its 11, which is about fourteen characters at
        // FONT_SMALL — and a row that has to shrink past FONT_SMALL to fit is the old
        // summary's mistake in a new place. Flight count lives on the Flights page.
        drawHero(dc, e.foilPct().format("%.0f") + "%", "on foil",
            PageModel.fmtTime(e.detector.foilTimeS) + " foil",
            "of " + PageModel.fmtTime(elapsed(c)),
            Ink.phaseFlying(), true);
        // The pill and the phone line are drawn as a PAIR: with a line to show, the pill
        // moves up one eyebrow line so the two together end where the pill alone used to,
        // and nothing else on the page moves. Without one, this is the shipped screen.
        var slot = phoneLineSlot(dc);
        drawSavedPill(dc, pillY(dc, slot == PHONE_LINE_TOP));
        if (slot != PHONE_LINE_NONE) {
            drawPhoneLine(dc, slot == PHONE_LINE_TOP ? phoneLineY(dc) : phoneLineLowY(dc));
        }
    }

    // ---- the direct transfer's progress (0.9.16, dev stream) ----
    // "phone 4/13" while the recording's pages cross to the iPhone, "phone ok" when the
    // stream is whole, nothing at all in every other stream and on every session that is
    // not being sent (DirectSend.statusLine is a `(:notdev)` null everywhere else, so this
    // call compiles in all three and draws in one).
    //
    // UNDER the pill and in the pill's own font: it is the same kind of sentence — an
    // acknowledgement of something the watch is doing on the rider's behalf — and the eyebrow
    // is where this page keeps those. Its own line rather than a suffix on SAVED, because
    // the two change on different clocks: SAVED is true the moment he presses it and this
    // counts for the next twenty seconds.
    //
    // It is dropped, never shrunk and never moved, when the line would touch the verdict's
    // digits: the giant is the page, and on the fenix 5 Plus family (whose hero block starts
    // 16 px higher than elsewhere, 0.9.13) that is a real collision and not a theoretical
    // one. A progress line worth overprinting the session's verdict for does not exist.
    hidden function drawPhoneLine(dc as Dc, y as Number) as Void {
        var line = DirectSend.statusLine();
        if (line == null) {
            return;
        }
        dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, y, Graphics.FONT_XTINY, line, CV);
    }

    // Where the phone line goes — and the answer moves the pill, so it has to be one
    // question asked once. `DirectSend.statusLine` is a `(:notdev)` null outside the dev
    // stream, so this is NONE there by construction and the page is byte for byte the one
    // that shipped.
    //
    // TOP is the shape Jan asked for: the pill lifts one eyebrow line and the status line
    // takes the band it vacated, so the pair ends where the pill alone used to. LOW is the
    // fallback for a font set whose top arc has nothing to give — the fenix 5 Plus family,
    // whose hero block starts 16 px higher than everyone else's (0.9.13), so savedY is
    // already pinned against the verdict's digits and there is no line above it. There the
    // status line goes to the bottom band instead, above the page dots, where that family
    // has room precisely because its hero block sits high.
    //
    // NONE when neither holds it. The bottom band is not free on a wide glass: the pill
    // itself lived there until 0.9.13 and on a 454 px screen it landed 6 px above the
    // verdict's second sub-row, which is why that slot is guarded here rather than assumed.
    static function phoneLineSlot(dc as Dc) as Number {
        if (DirectSend.statusLine() == null) {
            return PHONE_LINE_NONE;
        }
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        if (phoneLineY(dc) + hT / 2 < verdictDigitTop(dc) && pillY(dc, true) - hT / 2 >= 0) {
            return PHONE_LINE_TOP;
        }
        return phoneLineLowY(dc) - hT / 2 > heroBlockBottom(dc)
            ? PHONE_LINE_LOW : PHONE_LINE_NONE;
    }

    // The bottom slot: one eyebrow line above the page-position dots.
    static function phoneLineLowY(dc as Dc) as Number {
        return dc.getHeight() - dotBand(dc) - dc.getFontHeight(Graphics.FONT_XTINY);
    }

    // The lowest ink of the verdict page's hero block — the bottom of its second sub-row.
    // Everything that wants the bottom band has to clear it; the pill did not, in 0.9.13.
    static function heroBlockBottom(dc as Dc) as Number {
        var cy = dc.getHeight() / 2;
        var hN = RecordingView.inkH(dc, Graphics.FONT_NUMBER_THAI_HOT);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);
        var hM = dc.getFontHeight(Graphics.FONT_MEDIUM);
        return RecordingView.heroRowY(cy, hN, hT, hL, hM, 3, 2) + hM / 2;
    }

    // Ink centre of the pill. `lifted` is the phone line's presence: one XTINY line higher,
    // so the pair occupies the band the pill alone used to end at.
    //
    // The lift is measured against the WORD, not the brand badge — which matters on the
    // fenix 5 Plus family, where the lifted badge would leave the top of the glass by a few
    // pixels and the word would not (measured, 20 Sep 2026: pill 33 -> 14 on a 240 px glass
    // whose badge is 19 px tall). `lockupFits` is asked at the lifted y and answers no
    // there, so what that family gets is the word alone with the line under it — which is
    // the page that shipped before the badge existed, not a degraded one. Dropping the whole
    // line to keep a 26x19 mark on an acknowledgement would be the wrong trade.
    // Shared with the layout test.
    static function pillY(dc as Dc, lifted as Boolean) as Number {
        var y = savedY(dc);
        return lifted ? y - dc.getFontHeight(Graphics.FONT_XTINY) : y;
    }

    // Ink centre of the phone line: where the pill sits when it is NOT lifted, i.e. one full
    // eyebrow line under the lifted pill. Shared with the layout test, which asserts it
    // clears the verdict giant's cap line on every glass it is drawn on.
    static function phoneLineY(dc as Dc) as Number {
        return savedY(dc);
    }

    // ---- S2 Records ----
    // The live RECORDS page, verbatim — the sixth page unified with its live twin (0.9.18,
    // Jan's layout review: "make it identical to the live page").
    //
    // It was a bespoke hero until this round: the best 2 s as the giant, "10s 11.5" under it
    // and the session odometer under that. Two of those three numbers are the live page's own
    // two, drawn a different size in a different arrangement with a different word for each —
    // which is exactly how two screens showing one session start disagreeing about it, and
    // exactly the argument S3, S4, S5, S7 and S8 were already won on.
    //
    // The odometer is what the unification drops, and it is the one thing on this page that
    // had no live twin. It is not lost: the live Map page prints it under the trail and so
    // does S8. See docs/presentation.md, "The after-save pages and the live ones".
    hidden function drawRecords(dc as Dc, c as SessionController) as Void {
        _painter.drawRecordsBody(dc, c);
    }

    // ---- S3 Foil ----
    // The live FOIL table, verbatim, with the session's own final values in it — the third
    // page unified with its live twin, after Turns (S4) and the Story (S6).
    //
    // It used to be a bespoke hero: the longest flight's duration as the giant, its distance
    // under it, the flight count under that. Every one of those numbers is already on the
    // live foil table — `max` is that flight's two numbers, side by side in the two columns
    // that name them, and the count rides the title since this round — and the table says
    // two more besides (the shares and the totals) that the hero had no room for. Two pieces
    // of code drawing one session's foil numbers is how two screens start disagreeing about
    // it, which is the argument S4 and S6 were already won on.
    //
    // The arc comes with it, keyed to the time share exactly as on the water. What the rider
    // lands on after a save is therefore the page he has been reading all session, and the
    // only difference is that the numbers have stopped moving.
    hidden function drawFoil(dc as Dc, c as SessionController) as Void {
        _painter.drawFoilPage(dc, c, true);
        _painter.drawFoilBezel(dc, c);
    }

    // ---- S4 Turns ----
    // The live Turns page, VERBATIM — and since 0.9.18 with no flag at all.
    //
    // It had one: `live = false` showed the two streaks as their session BESTS alone, on the
    // argument that "the run he is on" stopped meaning anything when he pressed save. Jan's
    // layout review of 21 September 2026 asked for the after-save pages to be identical to the
    // live ones "wherever possible", and this was the last place a flag made two screens of
    // one session differ. The run he ended on IS a fact about the session — "I finished on a
    // run of seven" is the sentence a rider says in the car park — and showing "7/12" ashore
    // is the same reading of the same two numbers he had on the water one button press earlier.
    //
    // `drawTurnsBody` keeps its parameter: the streak row's two forms are a real distinction
    // and a renderer that can only draw one of them is a renderer that has to be edited to get
    // the other back. Nothing calls it with `false` today.
    hidden function drawTurns(dc as Dc, c as SessionController) as Void {
        _painter.drawTurnsBody(dc, c, true);
    }

    // ---- S5 Tacks & jibes ----
    // The live Tacks & jibes page, VERBATIM — no flag, because nothing on it means anything
    // different ashore: two counts and how many of each he flew through are the same four
    // numbers before and after the save. It is the fifth page unified with its live twin
    // (docs/presentation.md, "The after-save pages and the live ones") and the first that was
    // born unified.
    hidden function drawKinds(dc as Dc, c as SessionController) as Void {
        _painter.drawKindsBody(dc, c);
    }

    // ---- S6 Takeoffs ----
    // Only reached when the accelerometer produced something, so the numbers here are always
    // measured ones. "--" where a value genuinely was not measured, never a flattering 0.
    //
    // 0.9.18 rewrote every line of it. Jan read the shipped page off a sheet — "39/56",
    // "4.3 to foil", "+19 bpm" — and could not say what any of the three were, which is the
    // review checklist's pattern for a number that has been abbreviated past its meaning.
    // What they actually are:
    //
    //   39 of 56      takeoffs out of ATTEMPTS: he pumped 56 times and got up 39 of them
    //                 (PumpDetector.successes / attempts()). The slash said "per" as often as
    //                 it said "of"; the word does not.
    //   4.3 pumps     the average strokes it took, over every takeoff including the free ones
    //                 (`avgPumpsX10`, FIT session field 37). "to foil" named the destination
    //                 and not the number.
    //   last +19 bpm  what the LAST takeoff cost his heart — the rise from the effort's start
    //                 to its peak (HrCostTracker). It is one takeoff, not an average, and the
    //                 page said so nowhere: "+19 bpm" beside an average reads as an average.
    //                 Three words was the budget and "last +19 bpm" is three.
    //
    // The giant is the fraction, because it is the one the rider came for; the word above it
    // says what it counts and the detail line under it carries the other two. The detail line
    // sheds the HR half first where a chord cannot hold both — it is the narrowest question on
    // the page and the only one that is about one maneuver rather than the session.
    // It is NOT `drawHero`. Two reasons, and the first is a bug the file already warns about:
    // "39 of 56" carries LETTERS and drawHero fits its giant through the NUMBER ladder, whose
    // fonts have no letters — the page would have drawn two empty boxes between the digits
    // (RecordingView.fitGiant's header, the fenix 5 Plus PAUSED bug). So the fraction is drawn
    // as three pieces: the two counts in the number ladder and the word "of" between them at
    // FONT_XTINY, which is the house idiom for exactly this (the streak row, the P/S row, the
    // map's odometer) and is also Jan's rule of this round — numbers larger, words smaller.
    //
    // The second is the round glass: the fraction is the page's widest line, so it belongs on
    // the equator with the narrow lines above and below it. drawHero puts its giant at the TOP
    // of a four-row stack, which is right for a page whose giant is one short number and wrong
    // for one whose widest line is a three-part group.
    hidden function drawTakeoffs(dc as Dc, c as SessionController) as Void {
        var p = c.engine.pump;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = RecordingView.fitRadius(dc, false, false);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hV = RecordingView.inkH(dc, Graphics.FONT_NUMBER_MEDIUM);
        var hD = dc.getFontHeight(Graphics.FONT_SMALL);
        var got = p.successes.toString();
        var tried = p.attempts().toString();

        // row 0 — what the fraction counts
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, takeoffRowY(cy, hT, hV, hD, 0), Graphics.FONT_XTINY, TAKEOFF_WORD, CV);

        // row 1 — "39 of 56", on the equator
        var y = takeoffRowY(cy, hT, hV, hD, 1);
        var f = takeoffFont(dc, got, tried, RecordingView.rowBudget(radius, y - cy, hV));
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var x = cx - takeoffWidth(dc, got, tried, f) / 2;
        dc.setColor(Ink.effortPumping(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, got, LV);
        x += dc.getTextWidthInPixels(got, f);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, TAKEOFF_OF, LV);
        x += dc.getTextWidthInPixels(TAKEOFF_OF, Graphics.FONT_XTINY);
        dc.setColor(Ink.effortPumping(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, tried, LV);

        // rows 2 and 3 — the two smaller facts, ONE PER ROW. They started life on one row
        // with a " · " between them, which is the shape Jan sketched, and the sheet said no:
        // "4.3 pumps each · last +19 bpm" is 28 characters and measured 560 px against a
        // 406 px chord on a 454 px glass, so the bpm half was being shed on every watch
        // shipped — i.e. never drawn at all. Two narrow rows under the wide one is the same
        // page with both numbers on it, and it is what the round-glass rule asks for anyway.
        var pumps = takeoffPumps(c);
        var hr = takeoffCost(c);
        if (!pumps.equals("")) {
            drawRow(dc, cx, cy, radius, takeoffRowY(cy, hT, hV, hD, 2), TALLY_FLOOR, pumps,
                Graphics.COLOR_WHITE);
        }
        if (!hr.equals("")) {
            drawRow(dc, cx, cy, radius, takeoffRowY(cy, hT, hV, hD, 3), TALLY_FLOOR, hr,
                Graphics.COLOR_WHITE);
        }
    }

    // "4.3 pumps each" and "last +19 bpm", or "" where the number was never measured. Every
    // "--" the old page printed is simply absent: a takeoff that was never priced is not a
    // fact about the session, and a row that is not there says that better than a row of
    // dashes does. Both are shared with the layout test.
    static function takeoffPumps(c as SessionController) as String {
        var avg = c.engine.pump.avgPumpsX10();
        return avg > 0 ? (avg / 10.0).format("%.1f") + TAKEOFF_PUMPS : "";
    }

    static function takeoffCost(c as SessionController) as String {
        var cost = c.engine.hrCost.lastCostBpm;
        return cost < 0 ? "" : TAKEOFF_COST + cost.toString() + TAKEOFF_BPM;
    }

    // Row centres: 0 the word, 1 the fraction, 2 the pumps, 3 the HR cost — centred on the
    // block and then LIFTED, the same trade the Turns page makes and for the same reason.
    // One narrow row above the wide one and two below it is not a symmetric stack: on an
    // fr255 the fraction lands 22 px above the equator against a 42 px band, i.e. its ink
    // stops one pixel short of the centre line. The lift is exactly the distance that puts
    // the band's own centre on cy, and it costs the bottom row nothing it was using.
    // Shared with the layout test.
    static function takeoffRowY(cy as Number, hT as Number, hV as Number, hD as Number,
            row as Number) as Number {
        var y = cy - (hT + hV + 2 * hD) / 2 + takeoffBias(hT, hD);
        if (row == 0) { return y + hT / 2; }
        if (row == 1) { return y + hT + hV / 2; }
        if (row == 2) { return y + hT + hV + hD / 2; }
        return y + hT + hV + hD + hD / 2;
    }

    // The lift: what the two rows below the fraction outweigh the one above it by. It does
    // not depend on the fraction's own band, which is why it needs no cap — the rows either
    // side of the wide one are text lines, and the block is a text line taller at the bottom
    // than at the top by construction.
    static function takeoffBias(hT as Number, hD as Number) as Number {
        var want = hD - hT / 2;
        return want < 0 ? 0 : want;
    }

    // Width of the fraction group: two counts in `f` around the word at FONT_XTINY.
    static function takeoffWidth(dc as Dc, got as String, tried as String,
            f as Graphics.FontType) as Number {
        return dc.getTextWidthInPixels(got, f) + dc.getTextWidthInPixels(tried, f)
            + dc.getTextWidthInPixels(TAKEOFF_OF, Graphics.FONT_XTINY);
    }

    // NUMBER_MEDIUM down through the number ladder, then the text fonts to the FONT_SMALL
    // floor — the same ladder and the same floor a ladder row walks on the Turns page.
    static function takeoffFont(dc as Dc, got as String, tried as String,
            budget as Number) as Graphics.FontType {
        for (var i = 2; i < NUMBER_FONTS.size(); i++) {
            if (takeoffWidth(dc, got, tried, NUMBER_FONTS[i]) <= budget) {
                return NUMBER_FONTS[i];
            }
        }
        for (var i = 0; i < TALLY_FLOOR; i++) {
            if (takeoffWidth(dc, got, tried, TEXT_FONTS[i]) <= budget) {
                return TEXT_FONTS[i];
            }
        }
        return TEXT_FONTS[TALLY_FLOOR];
    }

    // ---- S7 Story ----
    // The timeline, verbatim. `history` is complete and untouched by the save, and this is
    // the page it was always really for: a coffee-in-hand read of the session arc, which is a
    // poor fit while riding and a perfect one here.
    hidden function drawStory(dc as Dc, c as SessionController) as Void {
        _painter.drawTimelinePage(dc, c);
    }

    // The recording view is reused as a PAINTER here, never shown: its timeline and bezel
    // renderers are pure functions of the engine, and duplicating them is how two screens
    // start disagreeing about the same session.
    hidden var _painter as RecordingView = new RecordingView();

    // ---- S8 Track ----
    // The breadcrumb as a SHAPE, tinted by foil state, scaled into the square inscribed in the
    // circle. The renderer moved to TrackDraw in 0.9.2 when the live map page stopped being the
    // firmware's MapTrackView and started being drawn the same way — a live trail and a
    // post-save trail that disagreed about which half of the session was flown would be the
    // same bug twice. No position marker here: the rider is ashore.
    hidden function drawTrack(dc as Dc, c as SessionController) as Void {
        var e = c.engine;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var box = trackBox(dc);
        // Same rule as the live page: inside a phone-sent snapshot the ground is drawn and the
        // snapshot's box is the frame (docs/watch-map-snapshot.md); otherwise auto-fit.
        var slot = e.trackN > 0 && e.trackLat != null && e.trackLon != null
            ? MapSnapshot.slotForPosition(e.trackLat[0], e.trackLon[0]) : null;
        var drawn;
        if (slot != null) {
            var frame = MapSnapshot.frame(slot, box);
            drawn = frame != null && TrackDraw.drawFramed(dc, e.trackLat, e.trackLon,
                e.trackFly, e.trackN, [cx, cy, box] as Array<Number>, false, frame,
                MapSnapshot.bitmap(slot, box));
        } else {
            drawn = TrackDraw.draw(dc, e.trackLat, e.trackLon, e.trackFly, e.trackN, cx, cy,
                box, false);
        }
        if (!drawn) {
            return;
        }
        // The SAME caption the live map page draws (0.9.18): the digits on the text ladder
        // from FONT_LARGE with "km" small beside them, not a FONT_SMALL string with a space
        // in it. This page and the live one are one trail drawn by one renderer, and a
        // distance printed two different sizes on them is the unification leaking at its one
        // remaining seam. A SPOT NAME, when the phone has sent one, still rides in front —
        // it is the one thing the saved page knows that the live page does not.
        var km = (e.distM / 1000.0).format("%.1f");
        var name = slot != null ? MapSnapshot.name(slot) : "";
        var y = trackCaptionY(dc);
        var radius = RecordingView.fitRadius(dc, false, false);
        var f = RecordingView.mapKmFont(dc, km,
            RecordingView.rowBudget(radius, y - cy, RecordingView.inkH(dc, TEXT_FONTS[0])));
        var w = RecordingView.mapKmWidth(dc, km, f);
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (!name.equals("")) {
            var sep = name + " · ";
            var wn = dc.getTextWidthInPixels(sep, Graphics.FONT_XTINY);
            var x = cx - (w + wn) / 2;
            dc.drawText(x, y, Graphics.FONT_XTINY, sep, LV);
            RecordingView.drawKm(dc, x + wn, y, km, f);
            return;
        }
        RecordingView.drawKm(dc, cx - w / 2, y, km, f);
    }

    // Ink centre of the distance caption: hung off the bottom of the track box. Its band is
    // FONT_LARGE's line since 0.9.18, the same as the live map's, so a long odometer moves
    // nothing. Shared with the layout test, which asserts it clears the page-position dots.
    static function trackCaptionY(dc as Dc) as Number {
        return dc.getHeight() / 2 + trackBox(dc) / 2
            + dc.getFontHeight(TEXT_FONTS[0]) / 2;
    }

    // Full side of the square the track is drawn in: the square inscribed in the glass, less
    // this screen's own margin (the page-position dots and the distance caption live in it).
    // The geometry itself is TrackDraw's, shared with the live map page. Shared with the
    // layout test.
    //
    // The margin grew by ONE LINE in 0.9.18 and it is measured rather than re-authored: the
    // caption stepped up from FONT_SMALL to FONT_LARGE's band, so the square gives up exactly
    // the difference between those two line heights on whatever glass this is — 18 px on a
    // fenix 8, 8 on a fenix 7S. Without it the taller caption's ink reaches the page-position
    // dots on the wide glasses, which is the one thing under this box that cannot move.
    static function trackBox(dc as Dc) as Number {
        var m = SUM_TRACK_MARGIN + dc.getFontHeight(TEXT_FONTS[0])
            - dc.getFontHeight(Graphics.FONT_SMALL);
        return TrackDraw.boxSide(dc.getWidth() / 2 - m);
    }

    static function trackScale(box as Number, w as Float, h as Float) as Float {
        return TrackDraw.scale(box, w, h);
    }

    // Neutral grey, not green. "Saved" is an acknowledgement, not a verdict on the session,
    // and the ladder's green is reserved for "that maneuver flew through". The old screen
    // made a FONT_MEDIUM green "Saved!" the largest element on a page whose subject is how
    // the session went — which is the one thing the rider already knows, since he pressed it.
    //
    // Since 0.9.5 the brand BADGE rides beside it: a horizontal lockup, badge then word,
    // the pair centred where the word alone used to be. Beside and not above, because there
    // is no "above" — the eyebrow already sits as high as the top arc allows — and because a
    // mark signing an acknowledgement is what a lockup is for. It stays subordinate by
    // construction: the badge is cut to the height of the LINE (asserted), so the pair is one
    // eyebrow's worth of ink on the arc over a giant that owns the middle of the page.
    hidden function drawSavedPill(dc as Dc, y as Number) as Void {
        var cx = dc.getWidth() / 2;
        var bw = Brand.badgeW();
        // A save that failed says so, in red, without the badge: nothing to sign.
        var ok = getApp().controller.lastSaveOk;
        var word = ok ? SUM_SAVED : SUM_NOT_SAVED;
        var textW = dc.getTextWidthInPixels(word, Graphics.FONT_XTINY);
        dc.setColor(ok ? Graphics.COLOR_WHITE : Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        // No room for the pair: the word alone, where it has always been.
        if (!ok || !lockupFits(dc, bw, Brand.badgeH(), textW, y)) {
            dc.drawText(cx, y, Graphics.FONT_XTINY, word, CV);
            return;
        }
        var left = cx - lockupW(dc, bw, textW) / 2;
        Brand.drawBadge(dc, left + bw / 2, y);
        dc.drawText(left + bw + savedGap(dc), y, Graphics.FONT_XTINY, SUM_SAVED,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // The lockup's geometry, shared with the layout test. The gap is a quarter of the line
    // the word is set in, so badge and word sit at the same distance apart on every glass.
    static function savedGap(dc as Dc) as Number {
        return dc.getFontHeight(Graphics.FONT_XTINY) / 4;
    }

    static function lockupW(dc as Dc, badgeW as Number, textW as Number) as Number {
        return badgeW + savedGap(dc) + textW;
    }

    // Is there room for the pair? Three ways there might not be, and the answer to all three
    // is the word on its own — which is the shipped page, so the fallback is not a degraded
    // screen, it is the previous one.
    //
    //   * the top of the glass, which the taller box can now reach;
    //   * the ARC, and which half is binding is not obvious — the badge is the taller box but
    //     the word is the further out, and the deeper corner changes with the glass, so ask
    //     both. The page paints the foil-% arc, so the radius is the verdict page's own;
    //   * the giant. The badge is the taller half of the pair, and it is held to the SAME
    //     yardstick the word has always been held to
    //     (`summaryPagesFitRoundDisplay`: an eyebrow clears `cy - fontHeight/2` of the number
    //     font). Measuring the badge against the hero BLOCK's top edge instead would be a
    //     stricter rule than the shipped screen already keeps — that edge is above the
    //     eyebrow on a 454 px glass, because the block is centred with a unit line and two
    //     sub-rows under the number and the digits themselves sit well inside their band.
    static function lockupFits(dc as Dc, badgeW as Number, badgeH as Number,
            textW as Number, y as Number) as Boolean {
        var cy = dc.getHeight() / 2;
        var half = lockupW(dc, badgeW, textW) / 2;
        if (y - badgeH / 2 < 0) {
            return false;
        }
        if (y + badgeH / 2 >= verdictDigitTop(dc)) {
            return false;
        }
        var limit = RecordingView.fitRadius(dc, false, true).toFloat();
        return Brand.cornerR(badgeW, badgeH, badgeW / 2 - half, y - cy) <= limit
            && Brand.cornerR(textW, RecordingView.inkH(dc, Graphics.FONT_XTINY),
                half - textW / 2, y - cy) <= limit;
    }

    // Ink centre of the SAVED pill: the TOP arc of the verdict page, mirroring where the
    // MAIN page keeps its clock. The bottom slot it first shipped in sat one line above the
    // dot band, which on a 454 px glass is 6 px above the verdict's second sub-row — two
    // baselines overprinting each other on the exact page the rider lands on. The top of
    // that page is empty, and an acknowledgement reads fine as an eyebrow.
    //
    // 0.9.13: ...and never lower than the verdict giant's own cap line. On the fenix 5 Plus
    // family the hero block, centred on the glass with its two sub-rows, starts 16 px above
    // where this eyebrow used to sit and SAVED printed over the "56%". The eyebrow clears the
    // digits by an eighth of its line, or moves up until it does; on a 454 px glass that is
    // 4 px above where it was, which no eye sees.
    static function savedY(dc as Dc) as Number {
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var y = dotBand(dc) + hT;
        var limit = verdictDigitTop(dc) - hT / 8;
        return y + hT / 2 > limit ? limit - hT / 2 : y;
    }

    // Where the verdict giant's DIGITS begin. The block is stacked on the ink band
    // (`RecordingView.inkH`, the ascent on a number font), but a number line that carries
    // leading sets its digits below the ascent's own top by half of that leading — on a
    // fenix 8 the THAI_HOT line is 210 px, the ascent 153, and the cap line sits 28 px under
    // the band's edge, which is exactly where the shipped eyebrow touches it. On the fenix 5
    // Plus family (ascent = line) the band's edge IS the cap line. Shared with the layout test.
    static function verdictDigitTop(dc as Dc) as Number {
        var cy = dc.getHeight() / 2;
        var hN = RecordingView.inkH(dc, Graphics.FONT_NUMBER_THAI_HOT);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);
        var hM = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var yc = RecordingView.heroRowY(cy, hN, hT, hL, hM, 0, 2);
        var line = dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT);
        var asc = Graphics.getFontAscent(Graphics.FONT_NUMBER_THAI_HOT);
        return yc - hN / 2 + (line - asc) / 2;
    }

    static function dotBand(dc as Dc) as Number {
        return dc.getHeight() / 12;
    }

    static function dotRadius(dc as Dc) as Number {
        var r = dc.getWidth() / 96;
        return r < 2 ? 2 : r;
    }

    // Which page you are on, as the same dot idiom StartView uses for GPS quality. One dot
    // per page the session actually has.
    hidden function drawDots(dc as Dc) as Void {
        var n = SummaryNav.count();
        if (n < 2) {
            return;
        }
        var r = dotRadius(dc);
        var step = 2 * r + SUM_DOT_GAP;
        var x0 = dc.getWidth() / 2 - (n * step - SUM_DOT_GAP) / 2 + r;
        var y = dc.getHeight() - dotBand(dc);
        var here = SummaryNav.wrap(SummaryNav.index);
        for (var i = 0; i < n; i++) {
            if (i == here) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x0 + i * step, y, r);
            } else {
                dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(x0 + i * step, y, r);
            }
        }
    }

    // Wall clock for the session, with the engine's own timer as the fallback: elapsedS is
    // captured at save from Activity.Info and is 0 on a run that reported none. It now lives
    // on the controller, because the live Turns page needs the same number for CPH and two
    // screens dividing by two different clocks is how one session grows two rates.
    static function elapsed(c as SessionController) as Float {
        return c.elapsedNowS();
    }
}

// UP/DOWN cycle the pages, START or BACK exits — the same navigation model as recording, so
// there is nothing new to learn. Taps are swallowed: a wet screen is not an input device.
class SummaryDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onNextPage() as Boolean {
        SummaryNav.step(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        SummaryNav.step(-1);
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    // START exits — except on the Track page with the post-save map switched on, where it
    // opens the firmware's map over the saved track (SavedMapView; an experiment, see there).
    function onSelect() as Boolean {
        if (SummaryNav.pageAt(SummaryNav.index) == SummaryNav.S_TRACK && SavedMap.available()) {
            WatchUi.pushView(new SavedMapView(), new SavedMapDelegate(), WatchUi.SLIDE_LEFT);
            return true;
        }
        System.exit();
    }

    function onBack() as Boolean {
        System.exit();
    }
}
