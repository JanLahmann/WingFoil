import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;
import WingFoilCore;

// Turns-page metrics, file scope so the static width helpers (shared with the layout
// test) can reach them — class consts are instance-scoped in Monkey C.
const TURNS_TALLY_SEP = " · ";
// Space between the coloured flew/touchdown/swim tally and the session success rate that
// shares its row. Wider than the tally's own separator so the two read as two groups.
const TURNS_OK_GAP = 14;

// The tally row never goes below TEXT_FONTS[TALLY_FLOOR] = FONT_SMALL. Below it a count is
// ~21 px of digit, under the readability floor — and the session whose tally is widest (30+
// turns, three two-digit counts) is exactly the session whose tally the rider wants to read.
// When the chord cannot hold the row at that size the row drops CONTENT instead of size:
// first the session verdict, then the " · " separators. See tallyContent().
const TALLY_FLOOR = 2;
const TALLY_SEP_NARROW = " ";
const TALLY_OK = 1;
const TALLY_SEPARATORS = 2;

// Main-page streak row: "dry 7 / 12" — the live no-fall run and the session's best.
const STREAK_CAPTION = "dry";
const STREAK_SEP = " / ";

// The Turns page carries BOTH runs, and says so in colour rather than in words:
// "streak: 2/5  7/11", one grey caption for the row and each run in its own ladder ink. The
// two words it used to spend ("fly", "dry") are gone — see drawStreakRow2 for why the colours
// say it better than the words did.
const STREAK_ROW_CAPTION = "streak:";
const STREAK_SEP_TIGHT = "/";

// The Turns page's bottom row: "49% ok  P29/S22". The words are XTINY and the numbers
// FONT_SMALL, which is what keeps this row inside a bottom-arc chord — the same caption trick
// the streak row uses. P/S is the ENTRY side, i.e. which tack he was on going in.
//
// Every space in these strings was spent and then taken back: with " % ok", "P " and " / "
// the row measured 301 px against a 291 px chord on a 416 px glass, so the whole P/S half —
// the one actionable number on the page — was being dropped on the 43 mm watch. It needs no
// spaces: the caption letters are XTINY grey and the counts FONT_SMALL white, and that size
// and colour break separates them far better than a space does.
// The share is the FLEW-THROUGH share — flewCount of the counted turns — and not the
// carried-speed score the row used to print. Two reasons, in order: it agrees with the green
// count in the tally above it BY CONSTRUCTION (same numerator, same denominator), so the page
// can no longer say "35 flew" in one row and a percentage nobody can derive from it in the
// next; and a score that mixes speed retention with the outcome is a sit-down number, which is
// what the phone is for. The stricter metric lives there now.
const TURNS_FLEW_SUFFIX = "% flew";
const TURNS_PORT = "P";
const TURNS_STBD = "S";
const TURNS_SIDE_SEP = "/";

// PAUSED banner. A word, not a value, so FONT_TINY is the right rung (docs review: XTINY and
// TINY are label sizes) — and a narrower banner is what lets it sit high enough on the glass
// to clear the rings entirely instead of punching a hole in them.
const PAUSED_TEXT = "PAUSED";
const PAUSED_FONT_IDX = 3;

// Cell geometry. The column offset is NOT a constant: the round display narrows fast below
// the equator, so each cell row splits the chord available at its own depth and only falls
// back to CELL_DX_MAX where there is room to spare.
const CELL_DX_MAX = 105;
const CELL_GUTTER = 10;

// Gap between a cell's glyph and the word beside it.
const GLYPH_GAP = 4;

// Bezel decorations, AS AUTHORED ON A 454 px GLASS. Every one of these is read through
// RecordingView.scaled(), never used raw, because they are ring geometry expressed as
// fractions of a radius: a 10 px ring is 4.4 % of the radius on a 454 px fenix 8 and 7.7 % on
// a 260 px fenix 8 Solar, so taken literally the narrow glass gives up nearly twice the share
// of its width — and it is the glass that can least afford it, because fitRadius now (rightly)
// refuses to draw text underneath any of it.
const REF_PX = 454;

// Foil-% bezel arc: pen width, and how far the arc's CENTRE line sits inside the glass.
// 5 + a pen of 6 puts the outer edge 2 px in — the same FIT_MARGIN the text respects.
const BEZEL_PEN = 6;
const BEZEL_INSET = 5;

// The flight-state ring on a HERO/MAIN page. It normally owns the bezel; when the page also
// asks for the foil-% arc it steps inside so the two nest instead of painting over each other.
const RING_INSET = 7;
const RING_PEN = 10;
const RING_INSET_NESTED = 16;
const RING_PEN_NESTED = 6;

// Safety margin inside the glass, in pixels, used by every fit. 2 px is deliberately tight:
// the shipped Clock page puts "23:59" in FONT_NUMBER_THAI_HOT within a few pixels of the
// bezel and it reads well, so anything more forgiving would shrink screens that are fine.
const FIT_MARGIN = 2;

// The GRID4 block sits this far above centre, as authored on a GRID_REF_PX glass. A 2x2 of
// FONT_LARGE cells plus a giant number is more content than a 454 px circle holds when
// centred — the bottom row's outer corners go off the glass. Lifting the block trades unused
// space at the top, where nothing is drawn, for cell width at the bottom, where the chord is
// the binding constraint.
//
// It is a RATIO, not a pixel count: 20 px was 4.4 % of the height it was authored at and
// 8.3 % of a 240 px fenix 7S — shoving the block furthest off centre on the narrow glass
// that can least afford it. RecordingView.gridBias() scales it, the way Glyphs.size() and
// StartView.dotRadius() already scale theirs.
//
// It grew from 20 to 28 when fitRadius learned about the foil-% arc: the shipped Session page
// carries foil %, so it DRAWS that arc, and the 11 px of radius the arc costs came straight
// out of the bottom row's chord — enough to push a "199:59" flight timer below FONT_MEDIUM.
// The lift buys those pixels back from the empty top of the screen.
const GRID_BIAS = 28;
const GRID_REF_PX = 454;

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

// The GRID4 pair band's ladder (see drawPairBand): the single giant's own font first, then the
// two text rungs a VALUE is allowed to use. PAIR_FLOOR is the last of them — FONT_MEDIUM, the
// readability floor for a number — and it is an index into this array, not into TEXT_FONTS.
var PAIR_FONTS as Array<Graphics.FontType> = [
    Graphics.FONT_NUMBER_MILD, Graphics.FONT_LARGE, Graphics.FONT_MEDIUM
];
const PAIR_FLOOR = 2;

// ---- the FOIL page's table (see drawFoilPage) ----
// A titled 3x2: one header, two column headers, three rows of two numbers. Everything on it
// is a foil number, so the word "foil" is said ONCE, at the top, instead of six times in six
// cell labels — which is the whole reason the page is a table and not a grid of cells.
//
// The column headers are UNITS, not categories ("min"/"km" rather than "time"/"dist"), because
// the units are the information the numbers are missing: "63:24" and "14.1" say nothing about
// what they are counting, while "56%" and "61%" under them read as exactly what they are — the
// share of the MINUTES flown and the share of the KILOMETRES flown.
const FOIL_TITLE = "foil";
const FOIL_COL_TIME = "min";
const FOIL_COL_DIST = "km";
// The row keys. `total` gives way to `tot` when the long word would cost the values their
// size: a key is already at the smallest font on the watch, so its LENGTH is the only thing
// left to trade, and three letters separate the two rows exactly as well as five do.
const FOIL_KEY_TOTAL = "total";
const FOIL_KEY_TOTAL_TIGHT = "tot";
const FOIL_KEY_MAX = "max";
const FOIL_KEY_GAP = 6;
// Values never go below TEXT_FONTS[FOIL_FLOOR] = FONT_SMALL, the readability floor every
// other number on this watch keeps.
const FOIL_FLOOR = 2;

// Timeline page bands (see drawTimelinePage). The two tall ones were authored for the fenix 8
// family, whose smallest glass is TL_REF_PX; RecordingView.stripH/sparkH keep them exactly as
// written at or above that width and scale them down below it.
const TL_REF_PX = 416;
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

    // Paging swaps the whole View, which fires onHide — so cancelling the celebration here
    // is precisely what PbFlash's module-level state exists to prevent (see its header). The
    // flash clears itself at FRAMES, which is what makes it safe to leave running; the
    // explicit stop() calls that matter are on the save/discard path in SessionController.
    function onHide() as Void {
    }

    function onUpdate(dc as Dc) as Void {
        var c = getApp().controller;
        var i = PageNav.index;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        // A page that shows foil % anywhere gets it a second time as an arc round the glass —
        // the one number the rider glances at without reading.
        var foilArc = PageModel.pageDrawsFoilArc(i);
        var layout = PageModel.layoutAt(i);
        // Pages that paint the flight-state ring, and therefore have less room for text.
        var ring = layout == PageModel.LAYOUT_HERO || layout == PageModel.LAYOUT_MAIN;
        if (layout == PageModel.LAYOUT_MAIN) {
            drawMainPage(dc, c, i, foilArc);
        } else if (layout == PageModel.LAYOUT_HERO) {
            drawHeroPage(dc, c, i, foilArc);
        } else if (layout == PageModel.LAYOUT_FOIL) {
            drawFoilPage(dc, c, foilArc);
        } else if (layout == PageModel.LAYOUT_GRID4) {
            drawGridPage(dc, c, i, foilArc);
        } else if (layout == PageModel.LAYOUT_CELLS2) {
            drawCells2Page(dc, c, i, foilArc);
        } else if (layout == PageModel.LAYOUT_RECORDS) {
            drawRecordsPage(dc, c);
        } else if (layout == PageModel.LAYOUT_TURNS) {
            drawTurnsPage(dc, c);
        } else if (layout == PageModel.LAYOUT_TIMELINE) {
            drawTimelinePage(dc, c);
        } else if (layout == PageModel.LAYOUT_CLOCK) {
            drawClockPage(dc, c, i, foilArc);
        } else {
            // LAYOUT_MAP lives in MapPageView and never reaches here; anything else is a
            // property the firmware handed us out of range — fall back to something readable.
            drawHeroPage(dc, c, i, foilArc);
            ring = true;
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
        // MAIN says PAUSED in its own top row — it is the only layout whose first row sits
        // where the banner wants to be, and a state word beats the time of day.
        if (c.state == SessionController.STATE_PAUSED && layout != PageModel.LAYOUT_MAIN) {
            drawPausedBanner(dc, fitRadius(dc, ring, foilArc));
        }
    }

    // The banner is the only thing on a recording page that is not part of a row stack, so
    // its position has to be DERIVED. It used to be `y = 18` with an opaque background, which
    // painted a black box from y 18 to 71 — straight across the flight ring, the nested ring
    // and the foil-% arc, so pausing bit a ~30 deg hole out of whichever ring the page was
    // showing, including the start of the arc, which is the one place a sweep is read from.
    //
    // Now the box is placed at the deepest y whose top corners still clear `radius` — the
    // same radius the page's text is fitted to, i.e. inside every ring the page draws. The
    // opaque background stays: it is what makes the word survive the PB flash painting over
    // the page underneath it.
    hidden function drawPausedBanner(dc as Dc, radius as Number) as Void {
        var font = TEXT_FONTS[PAUSED_FONT_IDX];
        var w = dc.getTextWidthInPixels(PAUSED_TEXT, font);
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
        dc.drawText(dc.getWidth() / 2, pausedBannerY(dc, w, radius), font, PAUSED_TEXT, CV);
    }

    // Ink centre of that banner. Shared with the layout test, which asserts the box corner
    // lands inside the ring rather than on it.
    static function pausedBannerY(dc as Dc, w as Number, radius as Number) as Number {
        var cy = dc.getHeight() / 2;
        var h = dc.getFontHeight(TEXT_FONTS[PAUSED_FONT_IDX]);
        var half = w / 2;
        var v = radius * radius - half * half;
        var dy = v > 0 ? Math.sqrt(v.toFloat()).toNumber() : 0;
        var y = cy - dy + h / 2;
        return y > cy ? cy : y;
    }

    // ---- foil-% bezel arc ----
    // 12 o'clock, clockwise, the phase teal over a dimmed track, hugging the inside of the
    // bezel. Teal and not green: this arc is "how much of the session was on the foil", a
    // PHASE, and green on this app means "that turn flew through" (docs/presentation.md).
    // Garmin's arc angles run COUNTER-clockwise from 3 o'clock, so 12 o'clock is 90 deg and
    // sweeping clockwise subtracts. Two primitive calls and integer maths: nothing allocates.
    // Public: the post-save Verdict page opens on this same arc, so the rider lands on a
    // shape he has been reading all session.
    function drawFoilBezel(dc as Dc, c as SessionController) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var pen = bezelPen(dc);
        var r = cx - bezelInset(dc) - pen / 2;
        dc.setPenWidth(pen);
        dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        var pct = c.engine.foilPct().toNumber();
        if (pct > 0) {
            dc.setColor(Ink.phaseFlying(), Graphics.COLOR_TRANSPARENT);
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
    // The whole screen goes the effort orange for ~700 ms with the new best on it. Frame
    // parity picks the shade, which is what turns a flash into a pulse (see PbFlash). Orange
    // and not green: a record is an EFFORT event, not a verdict, and green on this app is the
    // outcome ladder's "flew through" (docs/presentation.md).
    hidden function drawPbFlash(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var col = PbFlash.color();
        dc.setColor(col, col);
        dc.clear();
        var hHot = dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
        var hS = dc.getFontHeight(Graphics.FONT_SMALL);
        var radius = fitRadius(dc, false, false);
        var v = AppSettings.speedToDisplay(PbFlash.best2sMps).format("%.1f");
        var y = cy - (hHot + hS) / 2 + hS + hHot / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (hHot + hS) / 2 + hS / 2, Graphics.FONT_SMALL, "NEW PB", CV);
        // fitted like every other giant: the overlay happens to fit on every shipped variant,
        // but "happens to" is what finding 1.1 was made of.
        dc.drawText(cx, y, fitFont(dc, NUMBER_FONTS, 1, v,
            rowBudget(radius, y - cy, inkH(dc, Graphics.FONT_NUMBER_HOT))), v, CV);
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

    // The radius text may use. It is NOT simply the glass: a page that paints the flight ring
    // or the foil-% arc has already spent the outer 10-16 px of every radius on it, and a
    // fitter blind to that fills right up to the ring's inner edge — measured, the hero
    // giant's corner landed 0.1 px inside the ring on the 47 mm and 2.3 px OVER it on the
    // 43 mm, i.e. the speed number was drawn on top of the state ring. Every layout test
    // asserts against this function, so they inherit the correction for free.
    //
    // When a page carries both, the ring nests INSIDE the arc (RING_INSET_NESTED), so the
    // ring's inner edge is the binding constraint and the arc's is not.
    // A giant that has run out of NUMBER fonts. Every other giant on every other page starts
    // high enough in NUMBER_FONTS to have somewhere to step down to; the GRID4 giant does not
    // — its band is already FONT_NUMBER_MILD, the smallest of them — so when the chord is
    // narrower than MILD (a "199:59" timer on a page that also draws the foil-% arc) the only
    // honest answers are "clip" or "leave the number ladder". It leaves the ladder: a smaller
    // number is readable, a clipped one is not, and the row's band is unchanged either way.
    static function fitGiant(dc as Dc, text as String, from as Number,
            maxW as Number) as Graphics.FontType {
        for (var i = from; i < NUMBER_FONTS.size(); i++) {
            if (dc.getTextWidthInPixels(text, NUMBER_FONTS[i]) <= maxW) {
                return NUMBER_FONTS[i];
            }
        }
        return fitFont(dc, TEXT_FONTS, 0, text, maxW);
    }

    // A 454-authored bezel dimension on THIS glass, never below 1 px. Same treatment
    // Glyphs.size() and StartView.dotRadius() already give theirs.
    static function scaled(dc as Dc, authored as Number) as Number {
        var v = dc.getWidth() * authored / REF_PX;
        return v < 1 ? 1 : v;
    }

    static function ringInset(dc as Dc, nested as Boolean) as Number {
        return scaled(dc, nested ? RING_INSET_NESTED : RING_INSET);
    }

    static function ringPen(dc as Dc, nested as Boolean) as Number {
        return scaled(dc, nested ? RING_PEN_NESTED : RING_PEN);
    }

    static function bezelInset(dc as Dc) as Number {
        return scaled(dc, BEZEL_INSET);
    }

    static function bezelPen(dc as Dc) as Number {
        return scaled(dc, BEZEL_PEN);
    }

    static function fitRadius(dc as Dc, ring as Boolean, arc as Boolean) as Number {
        var cx = dc.getWidth() / 2;
        var r = cx - FIT_MARGIN;
        if (ring) {
            var inner = cx - ringInset(dc, arc) - ringPen(dc, arc) / 2 - FIT_MARGIN;
            if (inner < r) {
                r = inner;
            }
        }
        if (arc) {
            var a = cx - bezelInset(dc) - bezelPen(dc) - FIT_MARGIN;
            if (a < r) {
                r = a;
            }
        }
        return r;
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

    // The flight-state ring: the phase teal while flying, a visible dim ink off foil. It
    // steps inside when the page also carries the foil-% arc, so the bezel holds exactly one
    // ring at a time. Teal rather than green — the ring is a PHASE, and green on this app is
    // the outcome ladder's "flew through" (docs/presentation.md).
    hidden function drawStateRing(dc as Dc, c as SessionController, foilArc as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var flying = c.engine.detector.state == FlightDetector.STATE_ON;
        dc.setPenWidth(ringPen(dc, foilArc));
        dc.setColor(flying ? Ink.phaseFlying() : Ink.dim(), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, dc.getHeight() / 2, cx - ringInset(dc, foilArc));
        dc.setPenWidth(1);
    }

    // ---- MAIN: the default page 1 ----
    //
    // Five rows, and every one of them answers a question the rider actually asks between two
    // jibes: how fast did that run go, how are the turns going, am I still dry, and what time
    // is it. Deliberately NOT on this page: the session duration (he can see the sun) and the
    // flight timer (it is over by the time he looks). Both remain catalog metrics for any
    // other page's slots.
    //
    // THE GIANT IS NOT LIVE SPEED. A rider looks at his watch when he is NOT moving — coming
    // off a run, sitting on the board, sailing back — and at that moment the live number reads
    // 4 km/h and tells him nothing about the run he just did. The slot therefore defaults to
    // the best 10 s, and it is a CONFIGURABLE slot (pg1s1) like any HERO giant: a rider who
    // wants the live number back sets M_SPEED in Garmin Connect, and no code knows the
    // difference. That is also why the giant now carries a small caption — "best 10s" is not
    // self-evident the way a live speedometer was.
    //
    // The clock is a rung LARGER than it was and the giant a band SMALLER (FONT_NUMBER_MEDIUM,
    // ~88 px of digit — still three times the readability floor and by far the biggest thing
    // on the glass), and the unit that used to own a whole row now sits INLINE behind the
    // digits. Between them those two changes bought the outcome-dot strip its row without
    // anything else moving.
    hidden function drawMainPage(dc as Dc, c as SessionController, page as Number,
            foilArc as Boolean) as Void {
        var e = c.engine;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, true, foilArc);
        var hC = dc.getFontHeight(Graphics.FONT_LARGE);
        var hN = dc.getFontHeight(Graphics.FONT_NUMBER_MEDIUM);
        var hO = dc.getFontHeight(Graphics.FONT_LARGE);
        var hD = stripBandH(dc);
        var hK = dc.getFontHeight(Graphics.FONT_MEDIUM);

        drawStateRing(dc, c, foilArc);

        // row 0 — time of day, or PAUSED. This is the one layout whose top row sits exactly
        // where the pause banner wants to be, so it carries the state itself: a paused
        // session is more urgent than the time, and the swap costs no pixels.
        var paused = c.state == SessionController.STATE_PAUSED;
        var top = paused ? PAUSED_TEXT : PageModel.clockString();
        var y = mainRowY(cy, hC, hN, hD, hO, hK, 0);
        dc.setColor(paused ? Graphics.COLOR_YELLOW : Graphics.COLOR_LT_GRAY,
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, fitFont(dc, TEXT_FONTS, 0, top,
            rowBudget(radius, y - cy, inkH(dc, Graphics.FONT_LARGE))), top, CV);

        // row 1 — the giant, with its unit and caption inline behind the digits
        drawMainGiant(dc, c, page, cx, cy, radius, mainRowY(cy, hC, hN, hD, hO, hK, 1));

        // row 2 — every counted turn as one dot, oldest left. It sits DIRECTLY under the
        // giant, straddling the equator with it, because it is the widest thing on the page
        // and the equator is where the chord is widest: a dot strip pushed to the bottom arc
        // loses half its dots to the glass. The counts say how many; the strip says how they
        // arrived — three swims in a row is a different session from three swims in an hour,
        // and no count can tell them apart.
        y = mainRowY(cy, hC, hN, hD, hO, hK, 2);
        drawOutcomeStrip(dc, cx, y, rowBudget(radius, y - cy, hD), e.history);

        // row 3 — the outcome ladder as three counts. Colour AND position carry the verdict,
        // so it reads before the digits are in focus: green flew, orange touched, red swam.
        drawTally(dc, cx, mainRowY(cy, hC, hN, hD, hO, hK, 3), cy, radius, e.turns, "", 0);

        // row 4 — the dry run: how many turns since he last went in, and the session's best.
        drawStreakRow(dc, cx, mainRowY(cy, hC, hN, hD, hO, hK, 4), cy, radius, e.turns);
    }

    // The MAIN giant: a catalog metric in the page's s1 slot, its value in the number ladder
    // and its unit + caption as two XTINY lines wedged in beside the digits, bottom-aligned on
    // the digits' own baseline. The unit used to be a whole row of its own; inline it costs
    // nothing vertically and reads as part of the same number.
    hidden function drawMainGiant(dc as Dc, c as SessionController, page as Number,
            cx as Number, cy as Number, radius as Number, y as Number) as Void {
        var id = PageModel.slotAt(page, 0);
        if (id == PageModel.M_NONE) {
            id = PageModel.M_BEST_10S;      // a page 1 with no giant is not a page 1
        }
        var v = PageModel.value(id, c);
        var unit = PageModel.unitOf(id);
        var cap = PageModel.caption(id);
        var sufW = giantSuffixWidth(dc, unit, cap);
        var f = fitGiant(dc, v, 2,
            rowBudget(radius, y - cy, inkH(dc, Graphics.FONT_NUMBER_MEDIUM)) - sufW);
        var wv = dc.getTextWidthInPixels(v, f);
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var x = cx - (wv + sufW) / 2;
        dc.setColor(PageModel.color(id, c), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, v, LV);
        x += wv + GLYPH_GAP;
        var lines = (unit.equals("") ? 0 : 1) + (cap.equals("") ? 0 : 1);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        if (!unit.equals("")) {
            dc.drawText(x, suffixLineY(dc, y, f, 0, lines), Graphics.FONT_XTINY, unit, LV);
        }
        if (!cap.equals("")) {
            dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, suffixLineY(dc, y, f, 1, lines), Graphics.FONT_XTINY, cap, LV);
        }
    }

    // Width the inline suffix block takes from the giant's row budget: the wider of the two
    // XTINY lines, plus the gap that separates it from the digits. Shared with the layout test.
    static function giantSuffixWidth(dc as Dc, unit as String, cap as String) as Number {
        var wu = unit.equals("") ? 0 : dc.getTextWidthInPixels(unit, Graphics.FONT_XTINY);
        var wc = cap.equals("") ? 0 : dc.getTextWidthInPixels(cap, Graphics.FONT_XTINY);
        var w = wu > wc ? wu : wc;
        return w == 0 ? 0 : w + GLYPH_GAP;
    }

    // Ink centre of suffix line `line` (0 = unit, 1 = caption) of a `lines`-line block whose
    // bottom sits on the digits' baseline — approximated, as everywhere else in this file, by
    // the ink half-height below the row centre.
    static function suffixLineY(dc as Dc, y as Number, f as Graphics.FontType, line as Number,
            lines as Number) as Number {
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var base = y + inkH(dc, f) / 2 - hT / 2;
        return lines == 2 && line == 0 ? base - hT : base;
    }

    // Row centres for MAIN: 0 clock/state · 1 giant · 2 outcome dots · 3 outcome counts ·
    // 4 streak. Stacked from font heights only, like every other page, so the rows can never
    // overlap on any variant. Shared with the layout test.
    static function mainRowY(cy as Number, hC as Number, hN as Number, hD as Number,
            hO as Number, hK as Number, row as Number) as Number {
        var y = cy - (hC + hN + hD + hO + hK) / 2;
        if (row == 0) { return y + hC / 2; }
        if (row == 1) { return y + hC + hN / 2; }
        if (row == 2) { return y + hC + hN + hD / 2; }
        if (row == 3) { return y + hC + hN + hD + hO / 2; }
        return y + hC + hN + hD + hO + hK / 2;
    }

    // "dry 7 / 12" — the live no-fall run beside the session's longest (docs/algorithms.md
    // "Turn streaks"). Neutral ink on purpose: a run of not-falling is not a verdict on any
    // one turn, so it must not borrow the outcome ladder's green.
    hidden function drawStreakRow(dc as Dc, cx as Number, y as Number, cy as Number,
            radius as Number, t as TurnDetector) as Void {
        var now = t.dryStreak.toString();
        var best = t.bestDryStreak.toString();
        var f = streakFont(dc, now, best,
            rowBudget(radius, y - cy, inkH(dc, Graphics.FONT_MEDIUM)), 1);
        drawStreakPair(dc, cx - streakWidth(dc, now, best, f) / 2, y, STREAK_CAPTION, now,
            best, f, true);
    }

    // One "<caption> now / best" group, drawn from its LEFT edge and returning the x it ended
    // at, so a row can carry two of them. `showNow` off draws the best alone, which is what a
    // post-save page wants: "the current run" stops meaning anything once the rider is ashore.
    function drawStreakPair(dc as Dc, x as Number, y as Number, caption as String,
            now as String, best as String, f as Graphics.FontType,
            showNow as Boolean) as Number {
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, caption, LV);
        x += dc.getTextWidthInPixels(caption, Graphics.FONT_XTINY) + GLYPH_GAP;
        if (showNow) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, f, now, LV);
            x += dc.getTextWidthInPixels(now, f);
            dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, Graphics.FONT_XTINY, STREAK_SEP, LV);
            x += dc.getTextWidthInPixels(STREAK_SEP, Graphics.FONT_XTINY);
        }
        dc.setColor(showNow ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_WHITE,
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, best, LV);
        return x + dc.getTextWidthInPixels(best, f);
    }

    // Width of that block: an XTINY caption and separator around two numbers in `f`. Shared
    // with the layout test, which measures it at "99 / 99".
    static function streakWidth(dc as Dc, now as String, best as String,
            f as Graphics.FontType) as Number {
        return pairWidth(dc, STREAK_CAPTION, now, best, f, true);
    }

    static function pairWidth(dc as Dc, caption as String, now as String, best as String,
            f as Graphics.FontType, showNow as Boolean) as Number {
        var w = dc.getTextWidthInPixels(caption, Graphics.FONT_XTINY) + GLYPH_GAP
            + dc.getTextWidthInPixels(best, f);
        if (showNow) {
            w += dc.getTextWidthInPixels(now, f)
                + dc.getTextWidthInPixels(STREAK_SEP, Graphics.FONT_XTINY);
        }
        return w;
    }

    // The numbers step down from TEXT_FONTS[from] — the row's reserved band — and no further
    // than FONT_SMALL, which is the floor for anything carrying a digit.
    static function streakFont(dc as Dc, now as String, best as String,
            budget as Number, from as Number) as Graphics.FontType {
        for (var i = from; i < TALLY_FLOOR; i++) {
            if (streakWidth(dc, now, best, TEXT_FONTS[i]) <= budget) {
                return TEXT_FONTS[i];
            }
        }
        return TEXT_FONTS[TALLY_FLOOR];
    }

    // ---- HERO: one giant number, its unit line, and up to two rows under it ----
    // A fully configurable page: slot 1 is the giant, slots 2-3 the rows under it. The
    // foil-state ring is part of the hero style: on the water the colour, not the number, is
    // what you read first.
    hidden function drawHeroPage(dc as Dc, c as SessionController, page as Number,
            foilArc as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, true, foilArc);
        var hN = dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);
        var hM = dc.getFontHeight(Graphics.FONT_MEDIUM);

        drawStateRing(dc, c, foilArc);

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

    // ---- FOIL: the session's foil numbers as a titled 3x2 table ----
    //
    // It replaced the Session grid, and what it dropped is as much of the point as what it
    // kept. The grid showed the foil shares, the foil time, the longest flight, the session
    // DISTANCE and the flight COUNT — two of which are not foil numbers at all. The odometer
    // total and the flight count are still catalog metrics for any other page's slots (and the
    // count also has its own summary screen); this page is now one question asked twice, in
    // minutes and in kilometres:
    //
    //          foil
    //      min      km
    //      56%     61%          how much of it was flown
    //  tot 63:24   14.1         how much there was of it
    //  max  7:04    2.2         and the best single flight of it
    //
    // The column headers are said ONCE, at the top, and all three rows inherit them — that is
    // what makes it a table rather than three pairs of captioned cells, and it buys two rows of
    // glass back from captions that would have repeated the same two words three times.
    //
    // The distance column is ON-FOIL distance throughout (FlightDetector.foilDistM /
    // longestM), never the odometer: a "km" column whose top cell is a foil SHARE and whose
    // middle cell were the whole session would be two different denominators in one column.
    //
    // The bezel arc stays, and stays keyed to the TIME share: an arc is a sweep, a sweep can
    // only be one number, and the top-left cell is that number.
    hidden function drawFoilPage(dc as Dc, c as SessionController, foilArc as Boolean) as Void {
        var d = c.engine.detector;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, false, foilArc);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hV = dc.getFontHeight(Graphics.FONT_LARGE);
        var bias = gridBias(dc);
        var half = foilTableHalf(dc, radius, cy, hT, hV, bias);
        var keys = foilKeys(dc, half);
        var col = foilColumns(cx, half, foilKeyBlock(dc, keys));
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        // row 0 — the page's name, in the same grey every other page header wears
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, foilRowY(cy, hT, hV, 0, bias), Graphics.FONT_XTINY, FOIL_TITLE, CV);

        // row 1 — the two column headers, once, for the three rows under them
        var yh = foilRowY(cy, hT, hV, 1, bias);
        dc.drawText(col[1], yh, Graphics.FONT_XTINY, FOIL_COL_TIME, CV);
        dc.drawText(col[2], yh, Graphics.FONT_XTINY, FOIL_COL_DIST, CV);

        // row 2 — the two shares, teal, exactly as the pair band drew them: a PHASE tint, not
        // the outcome ladder's green (docs/presentation.md)
        var pt = PageModel.value(PageModel.M_FOIL_PCT, c);
        var pd = PageModel.value(PageModel.M_FOIL_DIST_PCT, c);
        drawFoilRow(dc, col, foilRowY(cy, hT, hV, 2, bias), "", pt, pd,
            foilFont(dc, [pt, pd], col[3]), Ink.phaseFlying(), LV);

        // rows 3 and 4 — the totals and the bests, white, and in ONE font: they are the two
        // halves of the same table, and a row that shrank on its own would read as a different
        // kind of number rather than as the same number a session later.
        var tt = PageModel.fmtTime(d.foilTimeS);
        var td = foilKm(d.foilDistM);
        var mt = PageModel.fmtTime(d.longestS);
        var md = foilKm(d.longestM);
        var f = foilFont(dc, [tt, td, mt, md], col[3]);
        drawFoilRow(dc, col, foilRowY(cy, hT, hV, 3, bias), keys[0], tt, td, f,
            Graphics.COLOR_WHITE, LV);
        drawFoilRow(dc, col, foilRowY(cy, hT, hV, 4, bias), keys[1], mt, md, f,
            Graphics.COLOR_WHITE, LV);
    }

    // One table row: an optional grey key at the block's left edge, then the two values on
    // their fixed columns. The key is left-justified and the values centred, which is what
    // keeps the columns lined up down the page whatever the keys measure.
    hidden function drawFoilRow(dc as Dc, col as Array<Number>, y as Number, key as String,
            a as String, b as String, f as Graphics.FontType, ink as Number,
            LV as Number) as Void {
        if (!key.equals("")) {
            dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(col[0], y, Graphics.FONT_XTINY, key, LV);
        }
        dc.setColor(ink, Graphics.COLOR_TRANSPARENT);
        dc.drawText(col[1], y, f, a, CV);
        dc.drawText(col[2], y, f, b, CV);
    }

    // Metres as the kilometres the column header promises. One decimal, like every other
    // distance on the watch.
    static function foilKm(metres as Float) as String {
        return (metres / 1000.0).format("%.1f");
    }

    // Row centres: 0 title · 1 column headers · 2 shares · 3 totals · 4 bests. Stacked from
    // font heights only, so no two rows can ever touch. `hV` is the band a value row reserves
    // — always FONT_LARGE's line height, whatever font the fit lands in, so shrinking a number
    // moves nothing.
    //
    // The block is LIFTED by the same bias the GRID4 page uses, and for the same reason: what
    // this page needs is width in its bottom row, the top of the glass has two XTINY words on
    // it and nothing else, and the trade is measured — at 454 px the lift takes the bottom
    // row's chord from 332 px to 370 px, which is the difference between a 199:59 worst case
    // fitting its column and overflowing it. Shared with the layout test.
    static function foilRowY(cy as Number, hT as Number, hV as Number, row as Number,
            bias as Number) as Number {
        var y = cy - (2 * hT + 3 * hV) / 2 - bias;
        if (row == 0) { return y + hT / 2; }
        if (row == 1) { return y + hT + hT / 2; }
        return y + 2 * hT + (row - 2) * hV + hV / 2;
    }

    // Half the width the TABLE may use: the narrowest of the three VALUE rows, each measured
    // at its own depth. One number for all of them, because a table whose columns move from
    // row to row is not a table.
    //
    // The header row is deliberately NOT in this minimum. It sits highest, so on a lifted
    // block it is the narrowest row on the page — but all it carries is two three-letter words
    // centred on columns that are already inside its chord, and letting it set the width would
    // hand the whole table the budget of its emptiest row. The layout test measures the two
    // headers where they are actually drawn instead.
    static function foilTableHalf(dc as Dc, radius as Number, cy as Number, hT as Number,
            hV as Number, bias as Number) as Number {
        var h = 0;
        for (var row = 2; row <= 4; row++) {
            var k = chordHalf(radius, foilRowY(cy, hT, hV, row, bias) - cy,
                inkH(dc, Graphics.FONT_LARGE));
            if (row == 2 || k < h) {
                h = k;
            }
        }
        return h;
    }

    // What one value column is wide, once the key column and the gutter are paid for.
    static function foilColWidth(half as Number, keyW as Number) as Number {
        return (2 * half - keyW - FOIL_KEY_GAP - CELL_GUTTER) / 2;
    }

    // The table's fixed geometry: [key LEFT edge, column 1 centre, column 2 centre, column
    // width]. The whole block — key column included — is centred on the glass, so the keys do
    // not push the numbers off centre; they are part of what is centred.
    static function foilColumns(cx as Number, half as Number,
            keyW as Number) as Array<Number> {
        var w = foilColWidth(half, keyW);
        var x0 = cx - half;
        var c1 = x0 + keyW + FOIL_KEY_GAP + w / 2;
        return [x0, c1, c1 + w + CELL_GUTTER, w];
    }

    // The key column's width, and with it which pair of words the page uses. The long words
    // give way when they would push the WORST CASE below its floor: what this table owes the
    // rider is six readable numbers, and a word that costs one of them its size is a word that
    // has to get shorter. Shared with the layout test.
    static function foilKeyWidth(dc as Dc, half as Number) as Number {
        return foilKeyBlock(dc, foilKeys(dc, half));
    }

    static function foilKeys(dc as Dc, half as Number) as Array<String> {
        var long = [FOIL_KEY_TOTAL, FOIL_KEY_MAX];
        var worst = dc.getTextWidthInPixels(PageModel.worstValue(PageModel.M_FOIL_TIME),
            TEXT_FONTS[FOIL_FLOOR]);
        return foilColWidth(half, foilKeyBlock(dc, long)) >= worst
            ? long : [FOIL_KEY_TOTAL_TIGHT, FOIL_KEY_MAX];
    }

    static function foilKeyBlock(dc as Dc, keys as Array<String>) as Number {
        var a = dc.getTextWidthInPixels(keys[0], Graphics.FONT_XTINY);
        var b = dc.getTextWidthInPixels(keys[1], Graphics.FONT_XTINY);
        return a > b ? a : b;
    }

    // The largest text font every one of `vals` fits its column in, floored at FONT_SMALL.
    // One font for the whole set: a table's column is one column.
    static function foilFont(dc as Dc, vals as Array<String>,
            colW as Number) as Graphics.FontType {
        for (var i = 0; i < FOIL_FLOOR; i++) {
            var fits = true;
            for (var j = 0; j < vals.size(); j++) {
                if (dc.getTextWidthInPixels(vals[j], TEXT_FONTS[i]) > colW) {
                    fits = false;
                }
            }
            if (fits) {
                return TEXT_FONTS[i];
            }
        }
        return TEXT_FONTS[FOIL_FLOOR];
    }

    // ---- GRID4: optional giant number on top, then a 2x2 of label/value cells ----
    hidden function drawGridPage(dc as Dc, c as SessionController, page as Number,
            foilArc as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, false, foilArc);
        var hG = dc.getFontHeight(Graphics.FONT_NUMBER_MILD);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);

        var giant = PageModel.slotAt(page, 0);
        var hasGiant = giant != PageModel.M_NONE;
        if (hasGiant) {
            var bias = gridBias(dc);
            var yg = gridRowY(cy, hG, hT, hL, 0, hasGiant, bias);
            var partner = PageModel.bandPartner(giant);
            if (partner != PageModel.M_NONE) {
                drawPairBand(dc, c, cx, cy, radius, yg, hG, giant, partner);
            } else {
                var gv = PageModel.value(giant, c);
                var gFont = fitGiant(dc, gv, 3,
                    rowBudget(radius, yg - cy, inkH(dc, Graphics.FONT_NUMBER_MILD)));
                dc.setColor(PageModel.color(giant, c), Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, yg, gFont, gv, CV);
            }
        }
        var rowBias = gridBias(dc);
        drawCellRow(dc, c, cx, cy, radius, gridRowY(cy, hG, hT, hL, 1, hasGiant, rowBias),
            PageModel.slotAt(page, 1), PageModel.slotAt(page, 2));
        drawCellRow(dc, c, cx, cy, radius, gridRowY(cy, hG, hT, hL, 2, hasGiant, rowBias),
            PageModel.slotAt(page, 3), PageModel.slotAt(page, 4));
    }

    // ---- the paired top band ----
    //
    // The GRID4 giant band draws TWO numbers whenever the giant slot holds a metric that has a
    // partner (PageModel.bandPartner) — on the shipped Session page, the foil TIME share and
    // the foil DISTANCE share. A rider reading "56 %" alone hears "and the other 44 % I was
    // sitting there"; the distance share (61 %) says how much of the water he actually crossed
    // flying, and neither number means much without the other.
    //
    // It moves nothing. The band is the height the single giant already reserved (hG, one
    // FONT_NUMBER_MILD line), the caption lives in that band's own SLACK above the digits, and
    // the two halves sit on the same two columns the 2x2 below them uses — so the page reads
    // as three rows of two, not as a giant with a grid under it. The slack is what picks the
    // font: a caption plus MILD's ink is taller than the band, so the pair steps one rung down
    // the ladder, which is also the rung two "100 %" need to share a chord that was sized for
    // one number. Never below FONT_MEDIUM: a value in a label font is not a value.
    //
    // The bezel arc is untouched and still keyed to foil TIME %: the arc is a sweep, and a
    // sweep can only be one number. The left half of the band is that number.
    hidden function drawPairBand(dc as Dc, c as SessionController, cx as Number, cy as Number,
            radius as Number, y as Number, band as Number, left as Number,
            right as Number) as Void {
        var lv = PageModel.value(left, c);
        var rv = PageModel.value(right, c);
        var lc = PageModel.bandCaption(left);
        var rc = PageModel.bandCaption(right);
        var f = pairFont(dc, lv, lc, rv, rc, band, radius, y, cy);
        var dx = pairColumn(dc, f, radius, y, cy);
        drawPairHalf(dc, cx - dx, y, lv, lc, f, PageModel.color(left, c));
        drawPairHalf(dc, cx + dx, y, rv, rc, f, PageModel.color(right, c));
    }

    // The band's two column centres: the SAME split the 2x2 below uses, taken at the digits'
    // own depth. Two things fall out of reusing cellColumns here, and both are why the band is
    // not simply two numbers centred as one block: the halves sit as far apart as their chord
    // allows, so the gap between them GROWS when the numbers are short (which is every real
    // session — "56%" and "61%" end up 46 px apart on a 454 px glass where a centred block
    // would leave 17), and the top row lines up with the grid under it instead of huddling.
    static function pairColumn(dc as Dc, f as Graphics.FontType, radius as Number,
            y as Number, cy as Number) as Number {
        return cellColumns(radius, pairRowY(dc, y, f, 1) - cy, inkH(dc, f))[0];
    }

    // One half of that band, centred on `x`: the word above, the number below, the pair of them
    // centred in the band. Ink heights, not line heights, because what has to fit is the band.
    hidden function drawPairHalf(dc as Dc, x as Number, y as Number, v as String,
            cap as String, f as Graphics.FontType, col as Number) as Void {
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var ink = inkH(dc, f);
        var top = y - (hT + ink) / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, top + hT / 2, Graphics.FONT_XTINY, cap, CV);
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, top + hT + ink / 2, f, v, CV);
    }

    // Ink centre of each of those two rows, 0 = caption, 1 = value. Shared with the layout
    // test, which measures both boxes against the chord at their own depth.
    static function pairRowY(dc as Dc, y as Number, f as Graphics.FontType,
            row as Number) as Number {
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var ink = inkH(dc, f);
        var top = y - (hT + ink) / 2;
        return row == 0 ? top + hT / 2 : top + hT + ink / 2;
    }

    // A half is as wide as its widest line — the number, in practice, since the captions are
    // one XTINY word.
    static function pairHalfWidth(dc as Dc, v as String, cap as String,
            f as Graphics.FontType) as Number {
        var wv = dc.getTextWidthInPixels(v, f);
        var wc = dc.getTextWidthInPixels(cap, Graphics.FONT_XTINY);
        return wv > wc ? wv : wc;
    }

    // What the block is TALL: the caption's line plus the number's ink. Must fit the band the
    // single giant reserved, or the pair would push into the 2x2 below it.
    static function pairBandHeight(dc as Dc, f as Graphics.FontType) as Number {
        return dc.getFontHeight(Graphics.FONT_XTINY) + inkH(dc, f);
    }

    // Does font `f` hold the whole block? Three constraints, and every one of them has bitten:
    // the block must fit the BAND's height (or the pair shoves the 2x2 off the glass); each
    // half must fit its own COLUMN, measured at the digits' own depth; and each caption must
    // still be inside the glass a value-height higher up, where the chord is narrower — on a
    // 454 px glass the caption row has ~70 px less of it, so a word that fits beside the digits
    // does not automatically fit above them.
    static function pairFits(dc as Dc, lv as String, lc as String, rv as String, rc as String,
            f as Graphics.FontType, band as Number, radius as Number, y as Number,
            cy as Number) as Boolean {
        if (pairBandHeight(dc, f) > band) {
            return false;
        }
        var col = cellColumns(radius, pairRowY(dc, y, f, 1) - cy, inkH(dc, f));
        var wMax = 2 * col[1];
        if (pairHalfWidth(dc, lv, lc, f) > wMax || pairHalfWidth(dc, rv, rc, f) > wMax) {
            return false;
        }
        var capHalf = chordHalf(radius, pairRowY(dc, y, f, 0) - cy,
            inkH(dc, Graphics.FONT_XTINY));
        return col[0] + dc.getTextWidthInPixels(lc, Graphics.FONT_XTINY) / 2 <= capHalf
            && col[0] + dc.getTextWidthInPixels(rc, Graphics.FONT_XTINY) / 2 <= capHalf;
    }

    // The band's own ladder: the single giant's font, then the two TEXT rungs a value may use.
    // The floor is FONT_MEDIUM, the readability floor for a number on this app — below it the
    // band would be lying about being the top of the page.
    static function pairFont(dc as Dc, lv as String, lc as String, rv as String, rc as String,
            band as Number, radius as Number, y as Number, cy as Number) as Graphics.FontType {
        for (var i = 0; i < PAIR_FLOOR; i++) {
            if (pairFits(dc, lv, lc, rv, rc, PAIR_FONTS[i], band, radius, y, cy)) {
                return PAIR_FONTS[i];
            }
        }
        return PAIR_FONTS[PAIR_FLOOR];
    }

    // Row centres for GRID4: 0 = giant number, 1 = top cell label, 2 = bottom cell label.
    // A cell's value sits (hT + hL) / 2 below its label. `hG` is the giant BAND — always
    // FONT_NUMBER_MILD's line height, because a 2x2 of FONT_LARGE cells plus anything taller
    // pushes the bottom row's corners off a 454 px circle. The whole block is lifted by
    // GRID_BIAS to buy that bottom row its width back.
    static function gridBias(dc as Dc) as Number {
        return dc.getHeight() * GRID_BIAS / GRID_REF_PX;
    }

    static function gridRowY(cy as Number, hG as Number, hT as Number, hL as Number,
            row as Number, hasGiant as Boolean, bias as Number) as Number {
        var cellH = hT + hL;
        var top = hasGiant ? cy - (hG + 2 * cellH) / 2 - bias : cy - cellH;
        if (row == 0) {
            return top + hG / 2;
        }
        var y = (hasGiant ? top + hG : top) + hT / 2;
        return row == 1 ? y : y + cellH;
    }

    // ---- CELLS2: two side-by-side cells, centred ----
    hidden function drawCells2Page(dc as Dc, c as SessionController, page as Number,
            foilArc as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);
        drawCellRow(dc, c, cx, cy, fitRadius(dc, false, foilArc), cells2RowY(cy, hT, hL),
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

    // A cell's label row: the WORD, or — when showLabels is off — the metric's glyph in its
    // place. Never both.
    //
    // They used to be drawn together, and the pair said one thing twice: a ruler beside the
    // word "km", a wing beside "flights". The glyph then had to be read as well as the word,
    // in a row that is 37 px of XTINY on a 454 px glass, and it pushed the word off the
    // column's centre for no information at all. The glyph earns its place only where the
    // word is not there — with labels off it is the entire content of the row, which is why
    // it stays for exactly that case: no cell may ever show a bare number.
    hidden function drawCellLabel(dc as Dc, x as Number, y as Number, id as Number) as Void {
        var s = Glyphs.size(dc);
        var label = AppSettings.showLabels ? PageModel.label(id) : "";
        if (label.length() > 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, Graphics.FONT_XTINY, label, CV);
            return;
        }
        var g = PageModel.glyph(id);
        if (g != Glyphs.G_NONE) {
            Glyphs.draw(dc, g, x, y, s, Graphics.COLOR_LT_GRAY);
        }
    }

    // Width of that block. Shared with the layout test, which measures the label row against
    // the chord exactly as it measures the value row.
    static function cellLabelWidth(dc as Dc, id as Number, s as Number,
            label as String) as Number {
        if (label.length() > 0) {
            return dc.getTextWidthInPixels(label, Graphics.FONT_XTINY);
        }
        return PageModel.glyph(id) != Glyphs.G_NONE ? s : 0;
    }

    // ---- RECORDS: live speed records, one giant number per block ----
    //
    // This was the one page that drew a giant WITHOUT going through fitFont, and it also
    // carried a `cy + 12` bias "because the top label otherwise clips the circle edge". With
    // the real font metrics that bias put the bottom number's 229 px of ink into a 206 px
    // chord on a 454 px glass — about 11 px sliced off each end, which on "99.9" costs the
    // leading digit and the decimal point. The bias is gone (the top label at its unbiased y
    // has a 231 px chord for ~100 px of text, so it was solving a problem that had already
    // been fixed elsewhere) and both numbers now walk the same NUMBER_FONTS ladder as every
    // other giant, so a knots reading or a three-digit value steps down instead of clipping.
    //
    // Records are EFFORT, not verdict: they wear the effort orange rather than plain white,
    // the same ink the PB celebration uses (docs/presentation.md).
    hidden function drawRecordsPage(dc as Dc, c as SessionController) as Void {
        var r = c.engine.records;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, false, false);
        var hHot = dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var ink = inkH(dc, Graphics.FONT_NUMBER_HOT);
        // unit only on the lower label, to keep the top one narrow
        var unit = " " + AppSettings.speedLabel();
        var best2s = AppSettings.speedToDisplay(r.best2sMps).format("%.1f");
        var best10s = AppSettings.speedToDisplay(r.best10sMps).format("%.1f");

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, recordsRowY(cy, hHot, hT, 0), Graphics.FONT_XTINY, "best 2s", CV);
        var y = recordsRowY(cy, hHot, hT, 1);
        dc.setColor(Ink.effortWindow(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, fitFont(dc, NUMBER_FONTS, 1, best2s,
            rowBudget(radius, y - cy, ink)), best2s, CV);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, recordsRowY(cy, hHot, hT, 2), Graphics.FONT_XTINY,
            "best 10s" + unit, CV);
        y = recordsRowY(cy, hHot, hT, 3);
        dc.setColor(Ink.effortWindow(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, fitFont(dc, NUMBER_FONTS, 1, best10s,
            rowBudget(radius, y - cy, ink)), best10s, CV);
    }

    // Row centres for RECORDS: 0/2 = the two labels, 1/3 = the two numbers. Stacked from font
    // heights and centred on the glass, with no bias of any kind. Shared with the layout test.
    static function recordsRowY(cy as Number, hHot as Number, hT as Number,
            row as Number) as Number {
        var y = cy - (2 * hHot + 2 * hT) / 2 + hT / 2;
        if (row == 0) { return y; }
        y += (hT + hHot) / 2;
        if (row == 1) { return y; }
        y += (hHot + hT) / 2;
        return row == 2 ? y : y + (hT + hHot) / 2;
    }

    // ---- TURNS: the outcome tally as the giant, both streaks, the dot strip, and the
    // session's verdict with its port/starboard split ----
    //
    // The hierarchy has been inverted twice now. It started with the tack/jibe COUNT as the
    // giant — a number a rider reads once an hour. It then promoted the LAST turn's score,
    // which answers "did that one count?" — but a rider looks at this page when he is sitting
    // on the board, not two seconds out of a jibe, and by then the last score is history.
    //
    // What survives that wait is the SESSION: how the day is going, three counts wide. So the
    // tally itself is the giant — three counts in the three ladder colours, colour and number
    // in one mark — and everything else on the page is the same question at a different
    // resolution: the strip is those turns in order, the streaks are how they clustered, and
    // the bottom row is what share worked and whether one side of the wind is costing him.
    //
    // The last outcome is not lost: it is the rightmost dot on the strip, in its own colour,
    // which is where a sequence naturally puts it.
    hidden function drawTurnsPage(dc as Dc, c as SessionController) as Void {
        drawTurnsBody(dc, c, true);
    }

    // `live` off is the post-save form: the streaks show the session's BESTS alone, because
    // "the run he is on" stops meaning anything the moment he is ashore. Everything else is
    // identical, which is the point — two screens showing one session's turns must not be two
    // pieces of code (the summary calls straight into this).
    function drawTurnsBody(dc as Dc, c as SessionController, live as Boolean) as Void {
        var t = c.engine.turns;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, false, false);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hG = dc.getFontHeight(Graphics.FONT_NUMBER_MEDIUM);
        var hK = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var hD = stripBandH(dc);
        var hS = dc.getFontHeight(Graphics.FONT_SMALL);
        var windSet = AppSettings.cfg.windDirection >= 0;

        // row 0 — the header, unchanged: which two maneuvers the counts below are, and the
        // axis that split them. `windLabel` marks an axis the WATCH estimated with a leading
        // "~" ("tack / jibe  ~SSW"), so the header never claims the rider named it.
        var y = turnsRowY(cy, hT, hG, hK, hD, hS, 0);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY,
            windSet ? "tack / jibe  " + AppSettings.windLabel() : "turns", CV);

        // row 1 — the giant: flew · touched · swam, in the ladder's own colours, with the
        // separators drawn as dim dots because the number fonts have no punctuation.
        drawGiantTally(dc, cx, turnsRowY(cy, hT, hG, hK, hD, hS, 1), cy, radius, t);

        // row 2 — both streaks. The dry run says "how long since I last went in", the flew run
        // "how long since I last even touched down"; bestFlewStreak <= bestDryStreak always.
        drawStreakRow2(dc, cx, turnsRowY(cy, hT, hG, hK, hD, hS, 2), cy, radius, t, live);

        // row 3 — the same turns as row 1, one dot each, in the order they happened.
        y = turnsRowY(cy, hT, hG, hK, hD, hS, 3);
        drawOutcomeStrip(dc, cx, y, rowBudget(radius, y - cy, hD), c.engine.history);

        // row 4 — the verdict, and the asymmetry underneath it. Which side of the wind he
        // enters on is the one thing on this page he can act on tomorrow.
        drawVerdictRow(dc, cx, turnsRowY(cy, hT, hG, hK, hD, hS, 4), cy, radius, t);
    }

    // The giant tally: three counts in a NUMBER font with two dim dots between them. Number
    // fonts are digit-only — no " · " to be had — so the separator is drawn, which is also
    // what lets it shrink with the digits instead of pinning a text font's punctuation beside
    // them. Starts at FONT_NUMBER_MEDIUM and steps down through MILD into the text ladder,
    // floored at FONT_SMALL like every other count on the watch.
    hidden function drawGiantTally(dc as Dc, cx as Number, y as Number, cy as Number,
            radius as Number, t as TurnDetector) as Void {
        var a = t.flewCount.toString();
        var b = t.touchdownCount.toString();
        var s = t.fellCount.toString();
        var f = giantTallyFont(dc, a, b, s,
            rowBudget(radius, y - cy, inkH(dc, Graphics.FONT_NUMBER_MEDIUM)));
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var sep = giantSepW(dc, f);
        var r = giantSepR(dc, f);
        var x = cx - giantTallyWidth(dc, a, b, s, f) / 2;
        var cols = [Ink.ladderFlew(), Ink.ladderTouchdown(), Ink.ladderFellIn()];
        var vals = [a, b, s];
        for (var i = 0; i < 3; i++) {
            if (i > 0) {
                dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x + sep / 2, y, r);
                x += sep;
            }
            dc.setColor(cols[i], Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, f, vals[i], LV);
            x += dc.getTextWidthInPixels(vals[i], f);
        }
    }

    // Separator slot and dot radius, both derived from the ink height of whatever font the
    // tally landed in, so the three groups keep their proportions on every variant.
    static function giantSepW(dc as Dc, f as Graphics.FontType) as Number {
        return inkH(dc, f) / 3;
    }

    static function giantSepR(dc as Dc, f as Graphics.FontType) as Number {
        var r = inkH(dc, f) / 14;
        return r < 2 ? 2 : r;
    }

    static function giantTallyWidth(dc as Dc, a as String, b as String, s as String,
            f as Graphics.FontType) as Number {
        return dc.getTextWidthInPixels(a, f) + dc.getTextWidthInPixels(b, f)
            + dc.getTextWidthInPixels(s, f) + 2 * giantSepW(dc, f);
    }

    // NUMBER_MEDIUM, then MILD, then down the text ladder to the FONT_SMALL floor. A count is
    // a value, and a value below FONT_SMALL is not readable at arm's length.
    static function giantTallyFont(dc as Dc, a as String, b as String, s as String,
            budget as Number) as Graphics.FontType {
        for (var i = 2; i < NUMBER_FONTS.size(); i++) {
            if (giantTallyWidth(dc, a, b, s, NUMBER_FONTS[i]) <= budget) {
                return NUMBER_FONTS[i];
            }
        }
        for (var i = 0; i < TALLY_FLOOR; i++) {
            if (giantTallyWidth(dc, a, b, s, TEXT_FONTS[i]) <= budget) {
                return TEXT_FONTS[i];
            }
        }
        return TEXT_FONTS[TALLY_FLOOR];
    }

    // The Turns page's streak row: "streak: 2/5  7/11". One grey word for the row, then the
    // two runs in the OUTCOME LADDER's own inks — green for the run of pure fly-throughs,
    // orange for the run that survives a touchdown; falling in breaks both, which is why there
    // is no red run to draw. That is exactly the vocabulary the coloured tally two rows above
    // has already taught, so the colours do the work the words "fly" and "dry" used to do, and
    // do it before the digits are in focus.
    //
    // This is not the ladder being borrowed for something else: each run is a COUNT OF RUNGS —
    // how many turns in a row came out green, how many came out anything but red — so it is the
    // ladder measured a second way (docs/presentation.md). The MAIN page's lone dry streak
    // stays neutral for the opposite reason: with no second run beside it there is nothing to
    // tell apart, and a colour there would read as a verdict on the rider rather than on turns.
    hidden function drawStreakRow2(dc as Dc, cx as Number, y as Number, cy as Number,
            radius as Number, t as TurnDetector, live as Boolean) as Void {
        var fNow = t.flewStreak.toString();
        var fBest = t.bestFlewStreak.toString();
        var dNow = t.dryStreak.toString();
        var dBest = t.bestDryStreak.toString();
        var budget = rowBudget(radius, y - cy, inkH(dc, Graphics.FONT_MEDIUM));
        var f = streakRow2Font(dc, fNow, fBest, dNow, dBest, budget, live);
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var x = cx - streakRow2Width(dc, fNow, fBest, dNow, dBest, f, live) / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, STREAK_ROW_CAPTION, LV);
        x += dc.getTextWidthInPixels(STREAK_ROW_CAPTION, Graphics.FONT_XTINY) + GLYPH_GAP;
        x = drawStreakRun(dc, x, y, fNow, fBest, f, live, Ink.ladderFlew());
        drawStreakRun(dc, x + TURNS_OK_GAP, y, dNow, dBest, f, live, Ink.ladderTouchdown());
    }

    // One run — "2/5" live, "5" once ashore — both numbers in `col`, the slash dim between
    // them. `showNow` off is the post-save form: "the run he is on" stops meaning anything the
    // moment he is out of the water, so S4 shows the two bests alone.
    function drawStreakRun(dc as Dc, x as Number, y as Number, now as String, best as String,
            f as Graphics.FontType, showNow as Boolean, col as Number) as Number {
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        if (showNow) {
            dc.setColor(col, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, f, now, LV);
            x += dc.getTextWidthInPixels(now, f);
            dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, f, STREAK_SEP_TIGHT, LV);
            x += dc.getTextWidthInPixels(STREAK_SEP_TIGHT, f);
        }
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, best, LV);
        return x + dc.getTextWidthInPixels(best, f);
    }

    static function streakRunWidth(dc as Dc, now as String, best as String,
            f as Graphics.FontType, showNow as Boolean) as Number {
        var w = dc.getTextWidthInPixels(best, f);
        if (showNow) {
            w += dc.getTextWidthInPixels(now, f)
                + dc.getTextWidthInPixels(STREAK_SEP_TIGHT, f);
        }
        return w;
    }

    static function streakRow2Width(dc as Dc, fNow as String, fBest as String, dNow as String,
            dBest as String, f as Graphics.FontType, live as Boolean) as Number {
        return dc.getTextWidthInPixels(STREAK_ROW_CAPTION, Graphics.FONT_XTINY) + GLYPH_GAP
            + streakRunWidth(dc, fNow, fBest, f, live) + TURNS_OK_GAP
            + streakRunWidth(dc, dNow, dBest, f, live);
    }

    static function streakRow2Font(dc as Dc, fNow as String, fBest as String, dNow as String,
            dBest as String, budget as Number, live as Boolean) as Graphics.FontType {
        for (var i = 1; i < TALLY_FLOOR; i++) {
            if (streakRow2Width(dc, fNow, fBest, dNow, dBest, TEXT_FONTS[i], live) <= budget) {
                return TEXT_FONTS[i];
            }
        }
        return TEXT_FONTS[TALLY_FLOOR];
    }

    // "69 % flew · P 29 / S 22" — the share of counted turns he flew through, and which side of
    // the wind he entered them on. Values in FONT_SMALL, every word around them XTINY, exactly
    // as the streak row does it, which is what keeps a nine-glyph row inside a bottom-arc
    // chord.
    //
    // The share is flewCount / turnCount, the same two numbers the green tally and the total
    // above it are drawn from, so this row can only ever agree with them.
    //
    // The P/S half is DROPPED, not shrunk, when the side counts are absent (no wind axis, so
    // no side to be on) or when the chord cannot hold it. A number that has to lie about its
    // size to fit is worse than a number that is not there.
    hidden function drawVerdictRow(dc as Dc, cx as Number, y as Number, cy as Number,
            radius as Number, t as TurnDetector) as Void {
        if (t.turnCount <= 0) {
            return;                 // no turns, no verdict: "0% flew" is not a fact yet
        }
        var pct = (t.flewCount * 100 / t.turnCount).toString();
        var p = t.portEntryCount.toString();
        var s = t.starboardEntryCount.toString();
        var sides = t.portEntryCount + t.starboardEntryCount > 0
            && verdictWidth(dc, pct, p, s, true)
                <= rowBudget(radius, y - cy, inkH(dc, Graphics.FONT_SMALL));
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var f = Graphics.FONT_SMALL;
        var x = cx - verdictWidth(dc, pct, p, s, sides) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, pct, LV);
        x += dc.getTextWidthInPixels(pct, f);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, TURNS_FLEW_SUFFIX, LV);
        if (!sides) {
            return;
        }
        x += dc.getTextWidthInPixels(TURNS_FLEW_SUFFIX, Graphics.FONT_XTINY) + TURNS_OK_GAP;
        dc.drawText(x, y, Graphics.FONT_XTINY, TURNS_PORT, LV);
        x += dc.getTextWidthInPixels(TURNS_PORT, Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, p, LV);
        x += dc.getTextWidthInPixels(p, f);
        dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, TURNS_SIDE_SEP, LV);
        x += dc.getTextWidthInPixels(TURNS_SIDE_SEP, Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, TURNS_STBD, LV);
        x += dc.getTextWidthInPixels(TURNS_STBD, Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, s, LV);
    }

    // Width of that row, with and without its port/starboard half. Shared with the layout
    // test, which measures it at "100 % flew · P 99 / S 99".
    static function verdictWidth(dc as Dc, pct as String, p as String, s as String,
            sides as Boolean) as Number {
        var f = Graphics.FONT_SMALL;
        var w = dc.getTextWidthInPixels(pct, f)
            + dc.getTextWidthInPixels(TURNS_FLEW_SUFFIX, Graphics.FONT_XTINY);
        if (!sides) {
            return w;
        }
        return w + TURNS_OK_GAP
            + dc.getTextWidthInPixels(TURNS_PORT, Graphics.FONT_XTINY)
            + dc.getTextWidthInPixels(p, f)
            + dc.getTextWidthInPixels(TURNS_SIDE_SEP, Graphics.FONT_XTINY)
            + dc.getTextWidthInPixels(TURNS_STBD, Graphics.FONT_XTINY)
            + dc.getTextWidthInPixels(s, f);
    }

    // The outcome ladder, and nothing else on the watch may borrow it (docs/presentation.md).
    // These are the design tokens, not Graphics.COLOR_GREEN/ORANGE/RED: the phase tint used
    // to be the same COLOR_GREEN, so on the Timeline page the foil bars and the outcome dots
    // — six rows apart, on one screen — were the same ink for two different meanings.
    static function outcomeColor(outcome as Number) as Number {
        if (outcome == TurnDetector.OUTCOME_FLEW) { return Ink.ladderFlew(); }
        if (outcome == TurnDetector.OUTCOME_TOUCHDOWN) { return Ink.ladderTouchdown(); }
        if (outcome == TurnDetector.OUTCOME_FELL) { return Ink.ladderFellIn(); }
        return Ink.ladderNone();
    }

    // Row centres for the Turns page: 0 header · 1 giant tally · 2 streaks · 3 outcome dots ·
    // 4 verdict + side split. Stacked from font heights only, so the rows can never overlap on
    // any variant. Shared with the layout test, which asserts every row clears the circle.
    static function turnsRowY(cy as Number, hT as Number, hG as Number, hK as Number,
            hD as Number, hS as Number, row as Number) as Number {
        var y = cy - (hT + hG + hK + hD + hS) / 2;
        if (row == 0) { return y + hT / 2; }
        if (row == 1) { return y + hT + hG / 2; }
        if (row == 2) { return y + hT + hG + hK / 2; }
        if (row == 3) { return y + hT + hG + hK + hD / 2; }
        return y + hT + hG + hK + hD + hS / 2;
    }

    // Width of the tally row: three counts, two separators, and — when it is being shown —
    // the session verdict after a wider gap so the two groups read as two groups.
    static function tallyWidth(dc as Dc, a as String, b as String, c as String,
            ok as String, sep as String, f as Graphics.FontType) as Number {
        var w = dc.getTextWidthInPixels(a, f) + dc.getTextWidthInPixels(b, f)
            + dc.getTextWidthInPixels(c, f) + 2 * dc.getTextWidthInPixels(sep, f);
        if (!ok.equals("")) {
            w += TURNS_OK_GAP + dc.getTextWidthInPixels(ok, f);
        }
        return w;
    }

    // What the row can afford to SHOW at font `f`, as a bitmask: TALLY_SEPARATORS for the
    // " · " between the counts, TALLY_OK for the session verdict. -1 = not even three bare
    // counts fit at this size.
    //
    // This is the "drop content, not size" rule. The old code stepped the font down instead,
    // and the measured worst case — three two-digit tallies plus "100% ok" — landed on
    // FONT_XTINY, about 21 px of digit, below the readability floor. The session that
    // produces that worst case (30+ turns) is exactly the session whose tally the rider wants
    // to read, so the row now sheds the verdict, then the separators, and only shrinks when
    // even the bare counts overflow.
    static function tallyContent(dc as Dc, a as String, b as String, c as String,
            ok as String, budget as Number, f as Graphics.FontType) as Number {
        if (tallyWidth(dc, a, b, c, ok, TURNS_TALLY_SEP, f) <= budget) {
            return TALLY_SEPARATORS | TALLY_OK;
        }
        if (tallyWidth(dc, a, b, c, "", TURNS_TALLY_SEP, f) <= budget) {
            return TALLY_SEPARATORS;
        }
        if (tallyWidth(dc, a, b, c, "", TALLY_SEP_NARROW, f) <= budget) {
            return 0;
        }
        return -1;
    }

    // The font the tally row lands in: the first from `from` at which SOME content set fits,
    // floored at TEXT_FONTS[TALLY_FLOOR] = FONT_SMALL. Below that a count is not readable at
    // arm's length, so the row would rather clip than lie about being legible — and in
    // practice it never gets there, because tallyContent has already dropped everything
    // droppable by then.
    static function tallyFont(dc as Dc, a as String, b as String, c as String, ok as String,
            budget as Number, from as Number) as Graphics.FontType {
        for (var i = from; i < TALLY_FLOOR; i++) {
            if (tallyContent(dc, a, b, c, ok, budget, TEXT_FONTS[i]) >= 0) {
                return TEXT_FONTS[i];
            }
        }
        return TEXT_FONTS[TALLY_FLOOR];
    }

    // The session-level number a tally row may carry at its end: the share of counted turns he
    // FLEW THROUGH — the green count over the total, the same arithmetic the Turns page's
    // bottom row prints. Empty until there is a turn to divide by, because "0% flew" before the
    // first jibe reads like a verdict on a session that has not happened.
    //
    // It used to be the carried-speed success score. That number left the watch in 0.8.2: it
    // mixes speed retention into an outcome and could disagree with the coloured counts beside
    // it, which is a page arguing with itself. The strict score lives in the phone analysis.
    static function flewText(turns as Number, flew as Number) as String {
        if (turns <= 0) {
            return "";
        }
        return (flew * 100 / turns).toString() + TURNS_FLEW_SUFFIX;
    }

    // "flew · touch · swim" counts in the ladder's own colours, centred as one block. `from`
    // is the TEXT_FONTS index the row's band was reserved at — 0 (FONT_LARGE) on the main
    // screen, TALLY_FLOOR (FONT_SMALL) on the Turns page — and `ok` is the session verdict,
    // empty when the caller does not want one on this row.
    // Public: the post-save Turns page draws the identical block. Two screens showing the
    // same three counts in the same three colours must not be two pieces of code.
    function drawTally(dc as Dc, cx as Number, y as Number, cy as Number,
            radius as Number, t as TurnDetector, ok as String, from as Number) as Void {
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var a = t.flewCount.toString();
        var b = t.touchdownCount.toString();
        var s = t.fellCount.toString();
        var budget = rowBudget(radius, y - cy, inkH(dc, TEXT_FONTS[from]));
        var f = tallyFont(dc, a, b, s, ok, budget, from);
        var mask = tallyContent(dc, a, b, s, ok, budget, f);
        if (mask < 0) {
            mask = 0;       // nothing fits even at the floor: draw the bare counts anyway
        }
        var sep = (mask & TALLY_SEPARATORS) != 0 ? TURNS_TALLY_SEP : TALLY_SEP_NARROW;
        var verdict = (mask & TALLY_OK) != 0 ? ok : "";
        var wSep = dc.getTextWidthInPixels(sep, f);
        var wa = dc.getTextWidthInPixels(a, f);
        var wb = dc.getTextWidthInPixels(b, f);
        var ws = dc.getTextWidthInPixels(s, f);
        var x = cx - tallyWidth(dc, a, b, s, verdict, sep, f) / 2;
        dc.setColor(Ink.ladderFlew(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, a, LV);
        dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wa, y, f, sep, LV);
        dc.setColor(Ink.ladderTouchdown(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wa + wSep, y, f, b, LV);
        dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wa + wSep + wb, y, f, sep, LV);
        dc.setColor(Ink.ladderFellIn(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wa + wb + 2 * wSep, y, f, s, LV);
        // ... and the session's own verdict at the end of the same row, in neutral grey so
        // the three coloured tallies stay the thing the eye lands on.
        if (!verdict.equals("")) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + wa + wb + ws + 2 * wSep + TURNS_OK_GAP, y, f, verdict, LV);
        }
    }

    // ---- TIMELINE: the session as a story ----
    // Three stacked bands: foil-fraction bars over the whole session, a max-speed sparkline
    // with the best-2s reference line, and the turn outcomes as coloured dots (newest right).
    // Every band is clipped to the chord at its own depth, so nothing runs off the glass; the
    // dot row simply shows as many of the most recent turns as fit.
    // Public: the post-save Story page is this page verbatim. The timeline is a
    // sit-down-with-a-coffee medium and a poor one-second glance, which is exactly the
    // right way round for a summary.
    function drawTimelinePage(dc as Dc, c as SessionController) as Void {
        var h = c.engine.history;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var radius = cx - TL_MARGIN;
        var strip = stripH(dc);
        var spark = sparkH(dc);

        // band 1: foil-fraction bars, between two rails.
        //
        // The rails are the whole reason this band is readable. A bar chart with one baseline
        // says "more is more" and nothing else — there was no way to know that a full-height
        // bar means "the whole of that half-minute was on the foil", so the band read as a
        // decorative sawtooth. Drawing the 100 % line as well turns it into an envelope: every
        // bar is now visibly a FRACTION of a fixed height, and the caption says which fraction.
        var top = timelineRowY(cy, hT, strip, spark, 1);
        var halfW = bandHalfWidth(radius, top, top + strip, cy);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, timelineRowY(cy, hT, strip, spark, 0), Graphics.FONT_XTINY,
            "on foil %", CV);
        dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - halfW, top + strip, cx + halfW, top + strip);
        dc.drawLine(cx - halfW, top, cx + halfW, top);
        var n = h.slotCount;
        if (n > 0) {
            var w = 2 * halfW;
            var barW = w / n;
            if (barW < 1) {
                barW = 1;
            }
            // PHASE teal, not the ladder's green: these bars and the outcome dots six rows
            // below them share one screen, and one ink for both meanings made the page lie.
            dc.setColor(Ink.phaseFlying(), Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i < n; i++) {
                var bh = h.foilPct[i] * strip / 100;
                if (bh > 0) {
                    dc.fillRectangle(cx - halfW + i * w / n, top + strip - bh, barW, bh);
                }
            }
        }

        // band 2: max-speed sparkline + best-2s reference
        top = timelineRowY(cy, hT, strip, spark, 3);
        halfW = bandHalfWidth(radius, top, top + spark, cy);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        // "top speed", not "speed": every point on this line is the FASTEST sample in its
        // slot, and a line labelled "speed" reads as an average — which would make the same
        // shape mean something the app never measured.
        dc.drawText(cx, timelineRowY(cy, hT, strip, spark, 2), Graphics.FONT_XTINY,
            "top speed " + AppSettings.speedLabel(), CV);
        var peak = h.peakCms();
        var ref = (c.engine.records.best2sMps * 100.0).toNumber();
        if (ref > peak) {
            peak = ref;
        }
        if (peak < 100) {
            peak = 100;
        }
        if (ref > 0) {
            var yRef = top + spark - ref * spark / peak;
            dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx - halfW, yRef, cx + halfW, yRef);
        }
        if (n > 1) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            var px = cx - halfW;
            var py = top + spark - h.maxCms[0] * spark / peak;
            for (var i = 1; i < n; i++) {
                var qx = cx - halfW + i * 2 * halfW / (n - 1);
                var qy = top + spark - h.maxCms[i] * spark / peak;
                dc.drawLine(px, py, qx, qy);
                px = qx;
                py = qy;
            }
            dc.setPenWidth(1);
        }

        // band 3: turn outcomes, newest on the right
        var yDots = timelineRowY(cy, hT, strip, spark, 5);
        halfW = bandHalfWidth(radius, yDots - TL_DOT_R, yDots + TL_DOT_R, cy);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, timelineRowY(cy, hT, strip, spark, 4), Graphics.FONT_XTINY, "turns", CV);
        drawOutcomeStrip(dc, cx, yDots, 2 * halfW, h);
    }

    // ---- the outcome strip ----
    // One dot per counted turn, in the order they happened, each in its verdict colour. It is
    // a TEXTURE, not a census: when there are more turns than the chord holds it shows the
    // most recent that fit and says nothing about the rest, because "how has the last while
    // gone" is the question a strip answers and a count is what answers the other one.
    //
    // Public and shared by three screens — the Timeline's bottom band, the MAIN page and the
    // Turns page (and through it the post-save Turns page). One visual language for one fact
    // means one function; the moment it was two, they would drift.
    function drawOutcomeStrip(dc as Dc, cx as Number, y as Number, avail as Number,
            h as SessionHistory) as Void {
        var shown = dotsShown(h.turnCount, avail);
        var pitch = 2 * TL_DOT_R + TL_DOT_GAP;
        var x0 = cx - (shown * pitch - TL_DOT_GAP) / 2 + TL_DOT_R;
        for (var i = 0; i < shown; i++) {
            dc.setColor(outcomeColor(h.turns[h.turnCount - shown + i]),
                Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x0 + i * pitch, y, TL_DOT_R);
        }
    }

    // The vertical band a strip reserves in a row stack: the dot plus a gap either side, so
    // the rows above and below it never sit against the ink. Shared with the layout test.
    static function stripBandH(dc as Dc) as Number {
        return 2 * TL_DOT_R + 2 * TL_DOT_GAP;
    }

    // Band heights for THIS glass. TL_STRIP_H / TL_SPARK_H were authored for the fenix 8
    // family (416-454 px) and every member of it keeps them verbatim. Taken literally on a
    // 240 px fenix 7S the three bands plus their labels fill 86 % of the height, which drives
    // every band down to a depth where the chord has collapsed — the dot row was left 88 px of
    // usable width, against 202 px once the bands scale.
    static function bandH(dc as Dc, authored as Number) as Number {
        var h = dc.getHeight();
        return h >= TL_REF_PX ? authored : h * authored / TL_REF_PX;
    }

    static function stripH(dc as Dc) as Number {
        return bandH(dc, TL_STRIP_H);
    }

    static function sparkH(dc as Dc) as Number {
        return bandH(dc, TL_SPARK_H);
    }

    // Timeline rows: 0 foil label · 1 strip TOP · 2 speed label · 3 sparkline TOP ·
    // 4 turns label · 5 dot-row centre. Stacked from font heights + the band heights, so
    // the bands can never collide on any variant.
    static function timelineRowY(cy as Number, hT as Number, strip as Number,
            spark as Number, row as Number) as Number {
        var total = 3 * hT + strip + spark + 2 * TL_DOT_R;
        var y = cy - total / 2;
        if (row == 0) { return y + hT / 2; }
        if (row == 1) { return y + hT; }
        if (row == 2) { return y + hT + strip + hT / 2; }
        if (row == 3) { return y + 2 * hT + strip; }
        if (row == 4) { return y + 2 * hT + strip + spark + hT / 2; }
        return y + 3 * hT + strip + spark + TL_DOT_R;
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
    hidden function drawClockPage(dc as Dc, c as SessionController, page as Number,
            foilArc as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, false, foilArc);
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
