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
        S_FLIGHTS = 2,
        S_TURNS = 3,
        S_TAKEOFFS = 4,
        S_STORY = 5,
        S_TRACK = 6
    }

    var _pages as Array<Number> = [S_VERDICT];

    // Which pages this session earned. Verdict/speed/flights/story always; turns only with a
    // turn to talk about, takeoffs only when the accelerometer was on and something happened,
    // the track only with a line to draw. A page that would say "0" is not a page.
    function build(c as SessionController) as Void {
        var e = c.engine;
        var p = [S_VERDICT, S_SPEED, S_FLIGHTS] as Array<Number>;
        if (e.turns.turnCount > 0) {
            p.add(S_TURNS);
        }
        if (e.pump.attempts() > 0 || e.pump.strokes > 0) {
            p.add(S_TAKEOFFS);
        }
        p.add(S_STORY);
        if (e.trackN >= 2) {
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

class SummaryView extends WatchUi.View {

    const CV = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var c = getApp().controller;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var page = SummaryNav.pageAt(SummaryNav.index);
        if (page == SummaryNav.S_VERDICT) {
            drawVerdict(dc, c);
        } else if (page == SummaryNav.S_SPEED) {
            drawSpeed(dc, c);
        } else if (page == SummaryNav.S_FLIGHTS) {
            drawFlights(dc, c);
        } else if (page == SummaryNav.S_TURNS) {
            drawTurns(dc, c);
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
        drawSavedPill(dc);
    }

    // ---- S2 Speed ----
    hidden function drawSpeed(dc as Dc, c as SessionController) as Void {
        var r = c.engine.records;
        drawHero(dc, AppSettings.speedToDisplay(r.best2sMps).format("%.1f"),
            "best 2s " + AppSettings.speedLabel(),
            "10s " + AppSettings.speedToDisplay(r.best10sMps).format("%.1f"),
            (c.engine.distM / 1000.0).format("%.1f") + " km",
            Ink.effortWindow(), false);
    }

    // ---- S3 Flights ----
    // `longestM` is tracked by FlightDetector on every flight and, until this page, was never
    // shown anywhere.
    //
    // The two rows are ordered so that the LONGEST FLIGHT's two numbers sit together: the
    // giant is its duration and row 1 is its distance, captioned "longest" so the pairing is
    // stated and not merely implied. With the flight COUNT between them — which is what
    // shipped in 0.8.1 — the eye read "7:04 · 31 · 2.2 km" as one series and the 2.2 km looked
    // like the session's distance, which it is not; it is how far he went on one flight.
    hidden function drawFlights(dc as Dc, c as SessionController) as Void {
        var d = c.engine.detector;
        drawHero(dc, PageModel.fmtTime(d.longestS), "longest flight",
            (d.longestM / 1000.0).format("%.1f") + " km longest",
            d.flightCount.toString() + " flights",
            Graphics.COLOR_WHITE, false);
    }

    // ---- S4 Turns ----
    // The live Turns page, VERBATIM, with one flag flipped: the streak row shows the session's
    // bests alone rather than "the run he is on", because the run he is on ended when he
    // pressed save. Everything else — the tally as the giant in the ladder's colours, the
    // outcome strip, the verdict with its port/starboard split — is the same question after
    // the session as during it, and asking it twice in two pieces of code is how two screens
    // start disagreeing about one session (the same reason S6 reuses the timeline).
    hidden function drawTurns(dc as Dc, c as SessionController) as Void {
        _painter.drawTurnsBody(dc, c, false);
    }

    // ---- S5 Takeoffs ----
    // Only reached when the accelerometer produced something, so the numbers here are always
    // measured ones. "--" where a value genuinely was not measured, never a flattering 0.
    hidden function drawTakeoffs(dc as Dc, c as SessionController) as Void {
        var p = c.engine.pump;
        var cost = c.engine.hrCost.lastCostBpm;
        var avg = p.avgPumpsX10();
        drawHero(dc, p.successes.toString() + "/" + p.attempts().toString(), "takeoffs",
            (avg > 0 ? (avg / 10.0).format("%.1f") : "--") + " to foil",
            cost < 0 ? "-- bpm" : "+" + cost.toString() + " bpm",
            Ink.effortPumping(), false);
    }

    // ---- S6 Story ----
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

    // ---- S7 Track ----
    // The breadcrumb as a SHAPE, tinted by foil state, scaled into the square inscribed in the
    // circle. The renderer moved to TrackDraw in 0.9.2 when the live map page stopped being the
    // firmware's MapTrackView and started being drawn the same way — a live trail and a
    // post-save trail that disagreed about which half of the session was flown would be the
    // same bug twice. No position marker here: the rider is ashore.
    hidden function drawTrack(dc as Dc, c as SessionController) as Void {
        var e = c.engine;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        if (!TrackDraw.draw(dc, e.trackLat, e.trackLon, e.trackFly, e.trackN, cx, cy,
                trackBox(dc), false)) {
            return;
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, trackCaptionY(dc), Graphics.FONT_SMALL,
            (e.distM / 1000.0).format("%.1f") + " km", CV);
    }

    // Ink centre of the distance caption: hung off the bottom of the track box. FONT_SMALL,
    // not XTINY — it is a value, and values do not go below the readability floor. Shared with
    // the layout test, which asserts it clears the page-position dots underneath it.
    static function trackCaptionY(dc as Dc) as Number {
        return dc.getHeight() / 2 + trackBox(dc) / 2
            + dc.getFontHeight(Graphics.FONT_SMALL) / 2;
    }

    // Full side of the square the track is drawn in: the square inscribed in the glass, less
    // this screen's own margin (the page-position dots and the distance caption live in it).
    // The geometry itself is TrackDraw's, shared with the live map page. Shared with the
    // layout test.
    static function trackBox(dc as Dc) as Number {
        return TrackDraw.boxSide(dc.getWidth() / 2 - SUM_TRACK_MARGIN);
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
    hidden function drawSavedPill(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var y = savedY(dc);
        var bw = Brand.badgeW();
        var textW = dc.getTextWidthInPixels(SUM_SAVED, Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        // No room for the pair: the word alone, where it has always been.
        if (!lockupFits(dc, bw, Brand.badgeH(), textW)) {
            dc.drawText(cx, y, Graphics.FONT_XTINY, SUM_SAVED, CV);
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
            textW as Number) as Boolean {
        var cy = dc.getHeight() / 2;
        var y = savedY(dc);
        var half = lockupW(dc, badgeW, textW) / 2;
        if (y - badgeH / 2 < 0) {
            return false;
        }
        if (y + badgeH / 2 >= cy - dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT) / 2) {
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
    static function savedY(dc as Dc) as Number {
        return dotBand(dc) + dc.getFontHeight(Graphics.FONT_XTINY);
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
    // captured at save from Activity.Info and is 0 on a run that reported none.
    static function elapsed(c as SessionController) as Float {
        return c.elapsedS > 0 ? c.elapsedS.toFloat() : c.engine.timerS;
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

    function onSelect() as Boolean {
        System.exit();
    }

    function onBack() as Boolean {
        System.exit();
    }
}
