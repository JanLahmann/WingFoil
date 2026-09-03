import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Layout maths for a data field, which — unlike the device app's own views — has no idea in
// advance how big its canvas is: the user drops it into a 1-, 2-, 3- or 4-field page and the
// system hands us whatever rectangle is left. Everything here is static and Dc-driven so the
// unit tests can measure the real device fonts and prove nothing clips, on any cell size.
//
// Four rules keep it readable on the water:
//   1. rows are stacked from dc.getFontHeight() only, so they can never overlap;
//   2. every row picks the LARGEST font that still fits its own width budget — and where the
//      cell reaches the rim of a round display that budget is the chord of the circle at the
//      row's deepest edge, not the bounding box, because a round display has no corners;
//   3. a stack in a cell against the rim leans away from it, into the spare room at the other
//      end, before it gives up a font size — the pixels above a top-anchored stack are empty
//      and the pixels beside a bottom-anchored one are missing, so the trade is free;
//   4. a cell that still cannot hold a layout's widest row does not get that layout: it steps
//      down a rung, because two numbers you can read beat three you cannot.
//
// Rules 2-4 used to apply only to the 1-field page, on the reasoning that a partial cell is a
// rectangle carved out of the middle of the glass and can use its full width. That is true of
// the middle of a stack and false at either end of it — the bottom half of a 2-field page IS
// the bottom of the circle — and the turn row lost its first and last characters to the bezel
// on every layout with a cell against the rim. The system will say which edges those are
// (WatchUi.DataField.getObscurityFlags(), valid inside onUpdate); place() turns that answer
// into the geometry the chord needs.
module FieldLayout {
    enum {
        SIZE_SMALL = 0,     // 3- or 4-field cell: 2 numbers, nothing else
        SIZE_WIDE = 1,      // 2-field cell (or a wide 3-field row): 3 rows
        SIZE_FULL = 2,      // 1-field page: the device app's Main page
        // RENDITIONS of SIZE_FULL, not sizes: classify() never returns them and fitCell()
        // never steps down into them. They are the two pages a full-screen cell shows once
        // the activity timer stops — the app's summary, alternating every few seconds.
        //
        // The pause is where a cycling display belongs and the ride is not. Jan's verdict on
        // cycling mid-ride: "nobody can look at the screen that long on the water"; on the
        // app's post-save pages: "data display after the activity is paused or stopped works
        // really nice". A rider who has stopped is actually reading, and a data field has no
        // buttons to page with, so a timer is the only way to give him the second page.
        REND_SUM_A = 3,     // the session: foil, time, flights, longest, distance
        REND_SUM_B = 4      // the turns: best speeds, count, split, outcomes, dry run
    }

    // Compute ticks each summary page holds before the other takes over. Five seconds is long
    // enough to read five labelled rows and short enough that a rider who wants the other page
    // does not feel he is waiting for it.
    const SUMMARY_TICKS = 5;

    // Which summary page is up after `ticks` paused seconds. Static arithmetic so the suite
    // can pin the cadence without a Dc.
    function summaryPage(ticks as Number) as Number {
        return (ticks / SUMMARY_TICKS) % 2 == 0 ? REND_SUM_A : REND_SUM_B;
    }

    // Pixels of bezel/edge margin kept clear on every side.
    const MARGIN = 4;

    // How many times fitRows() re-measures a stack after a row has changed size. See the
    // pass-2 comment there: shrinking a row moves the whole stack, so one round can be
    // optimistic. Every real cell settles in two.
    const REFITS = 3;

    // WatchUi.DataField.OBSCURE_*, mirrored so the layout maths — and the suite that drives it
    // with the real cell rectangles of all twelve layouts — never needs a DataField instance.
    // The values have been these four bits since CIQ 1.0.
    const EDGE_LEFT = 1;
    const EDGE_TOP = 2;
    const EDGE_RIGHT = 4;
    const EDGE_BOTTOM = 8;

    // Largest-first font ladders. fitFont() walks them and takes the first that fits.
    const NUM_FONTS = [Graphics.FONT_NUMBER_THAI_HOT, Graphics.FONT_NUMBER_HOT,
        Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD, Graphics.FONT_LARGE,
        Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY,
        Graphics.FONT_XTINY] as Array<Graphics.FontType>;
    const TEXT_FONTS = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL,
        Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontType>;

    // The widest string every row of every layout will ever show, indexed by SIZE_*, with the
    // ladder each of those rows walks. The fit is worst-case against these, so the display
    // cannot start clipping later in the session when the counts get bigger — and one table
    // means the drawing code, the size gate and the layout suite can never disagree about what
    // the worst case is. They did: the suite used to fit the WIDE turn row against
    // "TOUCH 100%", eight characters shorter than the "TOUCH 100% · 99/99" the field draws
    // there, which is most of the reason a clipped turn row got past it.
    // The SMALL and WIDE rows above the fixed bottom row are the rider's to choose since 0.9.5
    // (FieldSettings.applySlots rewrites rows 0 and 1 of the first two entries from
    // FieldMetrics.worst()), which is why this is a `var` that is written to exactly once per
    // settings load rather than a const. The values below are the DEFAULTS, and they are the
    // 0.9.4 rows character for character: an install that never opens the settings must fit,
    // draw and step down exactly as it did before.
    //
    // SIZE_FULL is the device app's Main page since 0.9.5 (foil %, a giant number, the outcome
    // dot ladder, the coloured tally, the dry run) rather than the five stacked values it used
    // to be. Row 2 of it is the dot ladder, and it is in the table as an EMPTY STRING on a
    // one-rung FONT_XTINY ladder because that is the honest way to say what it is: a row whose
    // HEIGHT is a font's and whose WIDTH is however much of the glass it is given (it draws
    // the dots that fit and no more, dotsShown()). One rung means the fitter cannot shrink it
    // and the drawing code always knows the band it got.
    // The character a worst-case row spends on the clean jibe's STAR (Glyphs.drawStar). The
    // glyph is not text and has to be budgeted as something, so it is drawn inside a box
    // exactly as wide as this character in the row's OWN font — which makes the string the
    // fitter measured and the ink the field draws the same width by construction, rather than
    // by a fixed pixel allowance that would be wrong at eight of the nine rungs of the ladder.
    // A digit and not a space, because the star is as wide as it is tall and a space is not.
    const STAR_STANDIN = "0";
    // What separates the outcome tally from the clean block beside it on the Main page. Two
    // spaces rather than the tally's own " · ", so the row reads as two groups and not as a
    // fourth rung of a three-rung ladder.
    const CLEAN_GAP = "  ";

    var WIDEST as Array<Array<String> > = [
        ["100%", "99 · 88:88"],
        ["100%", "99 · 88:88", "TOUCH 100% · 99/99"],
        ["100%", "88.8", "", "99 · 99 · 99  0 99 99.9", "99 / 99"],
        ["100%", "999", "199:59 / 199:59", "199:59", "88.8 km"],
        ["999", "99/99", "99 · 99 · 99", "0 99 99.9", "88.8/88.8", "99 / 99"]
    ];
    var DOT_ROW_FONTS as Array<Graphics.FontType> = [Graphics.FONT_XTINY]
        as Array<Graphics.FontType>;
    var LADDERS as Array<Array> = [
        [NUM_FONTS, TEXT_FONTS],
        [NUM_FONTS, TEXT_FONTS, TEXT_FONTS],
        [NUM_FONTS, NUM_FONTS, DOT_ROW_FONTS, TEXT_FONTS, TEXT_FONTS],
        [NUM_FONTS, NUM_FONTS, TEXT_FONTS, NUM_FONTS, TEXT_FONTS],
        [NUM_FONTS, TEXT_FONTS, TEXT_FONTS, TEXT_FONTS, TEXT_FONTS, TEXT_FONTS]
    ];

    // The row of each layout that gets the height the stack did not use, or -1 where every row
    // is equal and the spare stays spare.
    //
    // Pass 1 of fitRows gives every row the same slice of the cell, which is right for a stack
    // of peers and wrong for a page with a GIANT on it: five equal slices of a 454 px glass are
    // 89 px each, and the smallest number font on a fenix 8 is 113 px tall, so the app's Main
    // page came out with its giant in FONT_LARGE and 83 px of the glass left blank. The hero
    // row spends that blank space (growHero), one rung at a time, and stops the moment the
    // stack stops fitting — so it can only ever make a page bigger than the one that already
    // passed, never one that clips.
    //
    // SMALL and WIDE declare no hero on purpose: they are two or three numbers of equal
    // standing, and giving one of them the spare height would change what a 0.9.4 install sees
    // in every cell it has.
    var HERO as Array<Number> = [-1, -1, 1, -1, -1];

    // How much of a cell's height a hero-bearing stack may fill. The rest is air, and on a
    // round glass air at the ends is not waste: the chord at the top and bottom of a circle is
    // a fraction of the one across its middle, so a stack that fills its cell pushes its first
    // and last rows into the narrowest glass there is. Handing the hero every spare pixel and
    // letting pass 2 sort it out did exactly that on the fenix 8's 1-field page — the giant
    // reached FONT_NUMBER_HOT and the foil-% row above it was squeezed from FONT_LARGE to
    // FONT_XTINY paying for it, which is a page that traded a number the rider reads for one
    // he cannot miss.
    const HERO_STACK_PCT = 80;

    // ---- captions ----
    // The small word that says WHAT a row is, riding beside the value in FONT_XTINY. Jan's
    // verdict on the 0.9.4 store screenshots was the reason it exists: "hard to understand for
    // a user — what's being shown there?". A full-screen cell printing 56% / 31 · 1:36 /
    // FLEW 88% is five facts and no nouns, and a stranger reading the store page has no app to
    // have learned them from.
    //
    // It is the device app's rule, kept: no cell may ever show a bare number (RecordingView's
    // drawCellLabel). The app puts its word ABOVE the value because its pages are grids with a
    // label row per cell; the field's cell is a row STACK with no spare rows to give — nine
    // rows on the 260 px 1-field page of an fr255 would put every value at FONT_XTINY — so the
    // word goes BESIDE the value instead, exactly the way the app's own Main giant carries its
    // unit and caption inline. Same vocabulary as PageModel.label(): lowercase, one or two
    // short words, never the unit twice.
    //
    // SMALL and WIDE get one too — FieldSettings.applySlots writes their rows from
    // FieldMetrics.label(), because those rows are the rider's choice and the word has to
    // follow it — but they get it CONDITIONALLY. A caption is width taken out of the value's
    // window, and in the 78 px end band of a 7-field page or a 129 px quadrant on an fr255 the
    // word is bought with a font rung off the number. capsAffordable() is where that trade is
    // refused: a cell that would lose more than CAP_KEEP_PCT of its glyph height to the words
    // draws the numbers bare instead. That is this field's answer to the device app's
    // showLabels rule — the app substitutes a glyph where the word will not fit, and the
    // field has no glyph set compiled into it (Glyphs.mc reaches into the app's Ink and
    // DesignTokens), so what it does instead is decline.
    //
    // Entries are the WORST CASE, like WIDEST beside them: the giant's caption is "best 10s"
    // here because that is the longer of the two words it prints, and the live caption must
    // never be wider than the tabled one.
    const CAP_FONT = Graphics.FONT_XTINY;
    const CAP_GAP = 4;
    // How much of a stack's glyph height the captions may cost before they are dropped.
    const CAP_KEEP_PCT = 80;
    // The Main page's row 3 caption changed in 0.9.6 from "outcomes" to "cph", and the swap is
    // a measurement, not a preference. That row now carries the tally AND the clean block, and
    // on the widest glass there is a 405 px window for it: the value is 292 px and "outcomes"
    // was another 142, which overflowed — so the whole page lost its captions and the field
    // stopped looking like the app's Main page at all. "cph" costs 55, and it is the label the
    // row cannot do without: a bare "4.5" beside two counts means nothing, whereas the clean
    // COUNT is named by the star in front of it (a glyph exists so it can label without
    // spending a word — Glyphs.mc) and the three outcome counts are named by the three inks
    // they are drawn in, which is what that row has said since 0.9.5 and what the dot ladder
    // above it repeats. One word bought, two words that were already being said dropped.
    //
    // The summary's clean row does spell both out: it is the screen a stranger reads at a
    // standstill, it has a row to itself, and there is no tally beside it to borrow from.
    var CAPS as Array<Array<Array<String> > > = [
        [["foil"], ["flights"]],
        [["foil"], ["flights"], ["last turn"]],
        [["foil"], ["km/h", "best 10s"], ["turns"], ["cph"], ["dry run"]],
        [["foil"], ["flights"], ["foil / total"], ["longest"], ["dist"]],
        [["turns"], ["tack/jibe"], ["outcomes"], ["clean · cph"], ["best 2s/10s"],
            ["dry run"]]
    ];

    // Pixels a caption block takes out of its row's window: the wider of its lines, plus the
    // gap that separates it from the value. Zero for a row that has none, and the zero must
    // stay exactly zero — every uncaptioned row in the field is fitted by this function too.
    function capWidth(dc as Graphics.Dc, cap as Array<String>) as Number {
        var w = 0;
        for (var i = 0; i < cap.size(); i++) {
            var lw = dc.getTextWidthInPixels(cap[i], CAP_FONT);
            if (lw > w) {
                w = lw;
            }
        }
        return w == 0 ? 0 : w + CAP_GAP;
    }

    // How many lines of `cap` a row `rowH` tall can hold. Two lines are the app's Main-giant
    // form (unit over word); a row that cannot hold both keeps the LAST one, because the word
    // that names the number matters more than the unit beside it.
    function capLines(dc as Graphics.Dc, cap as Array<String>, rowH as Number) as Number {
        var n = cap.size();
        if (n < 2) {
            return n;
        }
        return 2 * dc.getFontHeight(CAP_FONT) <= rowH ? 2 : 1;
    }

    // Centre y of caption line `line` of a `lines`-line block centred on the row's own centre.
    function capLineY(dc as Graphics.Dc, y as Number, line as Number,
            lines as Number) as Number {
        var h = dc.getFontHeight(CAP_FONT);
        return lines < 2 ? y : y + (line == 0 ? -h / 2 : h / 2);
    }

    // A caption table of the right shape for a stack that wants none (the lock screen, and
    // every SMALL/WIDE cell).
    function noCaps(n as Number) as Array<Array<String> > {
        var out = new Array<Array<String> >[n];
        for (var i = 0; i < n; i++) {
            out[i] = [] as Array<String>;
        }
        return out;
    }

    // ---- the outcome dot ladder ----
    // One dot per counted turn in its verdict colour, oldest left — the device app's strip,
    // and the same rule: it is a TEXTURE, not a census. When there are more turns than the
    // chord holds it shows the most recent that fit, because "how has the last while gone" is
    // the question a strip answers and the tally under it answers the other one.
    //
    // The dot is sized off the GLASS, not off the cell: 6 px on the 454 px fenix 8 the strip
    // was authored on, scaled down so a 260 px fr255 gets a strip in the same proportion
    // rather than four fat dots. It is then capped by the band the row actually got.
    const DOT_R_REF = 6;
    const DOT_GAP_REF = 4;
    const DOT_REF_PX = 454;

    function dotGap(screenW as Number) as Number {
        var g = screenW * DOT_GAP_REF / DOT_REF_PX;
        return g < 2 ? 2 : g;
    }

    function dotRadius(band as Number, screenW as Number) as Number {
        var r = screenW * DOT_R_REF / DOT_REF_PX;
        if (r < 2) {
            r = 2;
        }
        // one pixel of air either side, so the strip never touches the row above or below
        var fit = (band - 2) / 2;
        if (r > fit) {
            r = fit;
        }
        return r < 1 ? 1 : r;
    }

    // How many of `count` dots fit `avail` pixels of chord.
    function dotsShown(count as Number, avail as Number, r as Number,
            gap as Number) as Number {
        var k = (avail + gap) / (2 * r + gap);
        if (k > count) {
            k = count;
        }
        return k < 0 ? 0 : k;
    }

    // Where a cell sits on a round glass, and therefore how much of each row the missing
    // corners eat. Built once per onUpdate from the cell rectangle and the obscurity flags;
    // null whenever there is nothing to correct for (see place()).
    class Glass {
        var y0 as Number;       // the cell's top edge, in SCREEN pixels
        var cx as Float;        // the GLASS's centre, in this cell's coordinates
        var cy as Float;        // the glass's centre, in screen coordinates
        var r as Float;         // the radius ink may use
        var lean as Number;     // +1: cell against the top rim, so a stack leans DOWN; -1: up

        function initialize(x0 as Number, top as Number, screenW as Number,
                screenH as Number, way as Number) {
            y0 = top;
            cx = screenW / 2.0 - x0;
            cy = screenH / 2.0;
            r = screenW / 2.0 - MARGIN;
            lean = way;
        }
    }

    // The cell's place on the glass, from the edges the system says are obscured.
    //
    // Horizontally the flags always answer: every cell Garmin lays out runs to the left rim,
    // the right rim, or both. Vertically they answer only at the ends of the stack, which is
    // where the answer matters — a band that touches neither rim was carved out of the middle
    // of the glass, where the chord is at its widest and the bounding box is the binding
    // constraint. Its offset is genuinely unknowable from in here (in a 5-field stack the
    // fourth band is nowhere near the centre, so "assume centred" would be a lie that reads as
    // maths), so such a cell gets no correction and keeps its full rectangle.
    function place(w as Number, h as Number, screenW as Number, screenH as Number,
            flags as Number, round as Boolean) as Glass? {
        if (!round) {
            return null;        // square glass: the rectangle is the truth
        }
        var top = (flags & EDGE_TOP) != 0;
        var bottom = (flags & EDGE_BOTTOM) != 0;
        if (!top && !bottom) {
            return null;
        }
        var x0 = 0;
        if ((flags & EDGE_LEFT) == 0 && (flags & EDGE_RIGHT) != 0) {
            x0 = screenW - w;
        }
        // A cell against ONE rim has a free edge to lean away towards. A cell against both is
        // the whole glass and has nowhere to go.
        var way = 0;
        if (top != bottom) {
            way = top ? 1 : -1;
        }
        return new Glass(x0, top ? 0 : screenH - h, screenW, screenH, way);
    }

    // Which layout a cell of this size gets. Thresholds are fractions of the device screen, so
    // one rule covers 416/454 AMOLED and 260/280 MIP fenix 8 variants. This is the room
    // question only; fitCell() asks the one that decides.
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

    // The layout this cell can actually CARRY, and the stack that carries it:
    // [size, fonts, lean, caps].
    //
    // `caps` is the caption set the fit was actually made against, which is CAPS[size] on a
    // cell with room for the words and the empty set on one without. It is RETURNED rather
    // than looked up again by the caller for the same reason WIDEST is one table: the row that
    // is drawn has to be the row that was measured, and a drawing pass that decided for itself
    // whether to caption could disagree with the fit that sized the font.
    //
    // classify() measures the room in fractions of the glass and is height-only above
    // SIZE_SMALL, which is how a 225 px quadrant of a 454 px watch — half the screen tall, and
    // half the screen WIDE — came to be handed the three-row layout whose turn row wants
    // 289 px at FONT_XTINY, the smallest font there is. This asks the question that decides:
    // laid out for real, with the lean and the ladder both spent, does every row still fit the
    // width the glass gives it? If not the cell steps down a rung, because two numbers you can
    // read beat three you cannot.
    function fitCell(dc as Graphics.Dc, w as Number, h as Number, screenW as Number,
            screenH as Number, g as Glass?) as Array {
        var size = classify(w, h, screenW, screenH);
        var caps = CAPS[size];
        var stack = fitStack(dc, w, h, WIDEST[size], LADDERS[size], caps, g, HERO[size]);
        // Two things a cell can give up, in the order they are worth giving up. The CAPTIONS
        // go first and the ROW goes second, because a turn line nobody labelled still says
        // FLEW 88 %, and a turn line that was dropped says nothing at all. Getting this order
        // wrong cost the 3-field top row its third row the first time it was written.
        while (!stackFits(dc, w, h, WIDEST[size], caps, stack, g)) {
            if (hasCaps(caps)) {
                caps = noCaps(WIDEST[size].size());
            } else if (size > SIZE_SMALL) {
                size--;
                caps = CAPS[size];
            } else {
                break;      // the smallest layout there is, drawn bare: nothing left to trade
            }
            stack = fitStack(dc, w, h, WIDEST[size], LADDERS[size], caps, g, HERO[size]);
        }
        // And a cell that CAN carry its captions may still not be able to afford them: the
        // words come off before the numbers shrink. The measure is the one fitStack already
        // uses to decide a lean — total glyph height — and captions that cost more than
        // 100 - CAP_KEEP_PCT per cent of it are words bought with the numbers' legibility,
        // which on a watch read at arm's length through spray is the wrong way round. A
        // full-screen cell always keeps them: it has the room, and the suite proves it.
        //
        // Inline rather than a capsAffordable() helper, and that is not a style choice: one
        // more frame on the fitCell -> fitStack -> fitRows -> fitFont chain overflows the
        // interpreter's stack when the layout suite calls fitCell from a frame of its own.
        if (size != SIZE_FULL && hasCaps(caps)) {
            var bare = fitStack(dc, w, h, WIDEST[size], LADDERS[size],
                noCaps(WIDEST[size].size()), g, HERO[size]);
            if (stackInk(dc, stack[0] as Array<Graphics.FontType>) * 100
                    < stackInk(dc, bare[0] as Array<Graphics.FontType>) * CAP_KEEP_PCT) {
                caps = noCaps(WIDEST[size].size());
                stack = bare;
            }
        }
        return [size, stack[0], stack[1], caps] as Array;
    }

    function hasCaps(caps as Array<Array<String> >) as Boolean {
        for (var i = 0; i < caps.size(); i++) {
            if (caps[i].size() > 0) {
                return true;
            }
        }
        return false;
    }

    // One of the summary renditions, fitted to a cell that fitCell has already called FULL.
    // Null when the stack does not survive it, and the caller falls back to the live page: a
    // face that clips is worse than a face that is merely the wrong one for the moment.
    function fitRendition(dc as Graphics.Dc, w as Number, h as Number, idx as Number,
            g as Glass?) as Array? {
        var stack = fitStack(dc, w, h, WIDEST[idx], LADDERS[idx], CAPS[idx], g,
            HERO[idx]);
        if (!stackFits(dc, w, h, WIDEST[idx], CAPS[idx], stack, g)) {
            return null;
        }
        return stack;
    }

    // Fonts and lean for one set of rows in one cell: [fonts, lean].
    //
    // The centred stack is tried first and kept unless leaning away from the rim buys a bigger
    // font somewhere, so a cell that was never in trouble is left exactly where it always was.
    function fitStack(dc as Graphics.Dc, w as Number, h as Number, texts as Array<String>,
            ladders as Array, caps as Array<Array<String> >, g as Glass?,
            hero as Number) as Array {
        var fonts = fitRows(dc, w, h, texts, ladders, caps, g, 0, hero);
        if (g == null || g.lean == 0) {
            return [fonts, 0] as Array;
        }
        var centred = [fonts, 0] as Array;
        var leaned = [fitRows(dc, w, h, texts, ladders, caps, g, g.lean, hero),
            g.lean] as Array;
        var inkC = stackInk(dc, fonts);
        var inkL = stackInk(dc, leaned[0] as Array<Graphics.FontType>);
        if (inkL > inkC) {
            return leaned;
        }
        // A tie on ink is not a tie on FIT. Both stacks bottom out at FONT_XTINY in the 113 px
        // top band of a 4-field page, so neither can buy a bigger font by leaning — but the
        // centred one sits 195 px above the middle of the glass, where the chord is 128 px,
        // and the leaned one sits low enough in the same band to have 227. Where the centred
        // stack overflows and the leaned one does not, the lean is free and it is taken.
        if (inkL == inkC && !stackFits(dc, w, h, texts, caps, centred, g)
                && stackFits(dc, w, h, texts, caps, leaned, g)) {
            return leaned;
        }
        return centred;
    }

    // How much glyph a set of fonts is worth. Bigger is better, and a tie keeps the centred
    // stack — that is what makes the lean invisible everywhere it is not needed.
    function stackInk(dc as Graphics.Dc, fonts as Array<Graphics.FontType>) as Number {
        var total = 0;
        for (var i = 0; i < fonts.size(); i++) {
            total += dc.getFontHeight(fonts[i]);
        }
        return total;
    }

    // Does this stack's worst case survive in this cell, once fitStack has spent everything it
    // has? fitRows() has already stepped every row down to the smallest font in its ladder if
    // that is what it took, so a row that still overflows here overflows at any size.
    function stackFits(dc as Graphics.Dc, w as Number, h as Number, texts as Array<String>,
            caps as Array<Array<String> >, stack as Array, g as Glass?) as Boolean {
        var fonts = stack[0] as Array<Graphics.FontType>;
        var lean = stack[1] as Number;
        var heights = heightsOf(dc, fonts);
        for (var i = 0; i < texts.size(); i++) {
            var y = stackY(h, heights, i, lean);
            if (y - heights[i] / 2 < 0 || y + heights[i] / 2 > h) {
                return false;       // the stack does not even fit the cell's height
            }
            if (rowInk(dc, texts[i], fonts[i], caps[i])
                    > rowWindow(w, y, heights[i], g)[1]) {
                return false;
            }
        }
        return true;
    }

    // What a row actually puts on the glass: the value in its own font, plus the caption block
    // riding beside it. One function so the fitter, the drawing code and the layout suite can
    // never disagree about how wide a captioned row is — the same reason WIDEST is one table.
    function rowInk(dc as Graphics.Dc, text as String, font as Graphics.FontType,
            cap as Array<String>) as Number {
        return dc.getTextWidthInPixels(text, font) + capWidth(dc, cap);
    }

    // The horizontal window a row of height rowH centred at cell-local y actually has, in CELL
    // coordinates: [centre, width]. It is the cell's own box intersected with the chord of the
    // glass at the row's deepest edge — the same geometry the device app's Turns-page test
    // asserts, applied ahead of time instead of after the fact.
    //
    // The centre is part of the answer because a corner cell is not centred on the glass: the
    // chord runs out on the inboard side of such a cell long before the outboard one, and a
    // row glued to the middle of its own cell loses characters at one end that it could have
    // kept by sliding towards the middle of the WATCH.
    //
    // When the two do not overlap at all the model has run out — the row's font BOX has left
    // the glass even though its ink has not, which happens in the 78 px top band of a 7-field
    // page — and the answer is the one the field gave before any of this existed: a width of
    // zero (so the ladder walks to its smallest font) at the centre of the cell.
    //
    // Note the whole font box is budgeted, not the ink inside it, which is a few pixels either
    // side of pessimistic. That is the pessimism the 1-field page has always been fitted with,
    // and one rule for every cell is worth more here than the odd recovered pixel.
    function rowWindow(w as Number, y as Number, rowH as Number, g as Glass?) as Array<Number> {
        var lo = MARGIN.toFloat();
        var hi = (w - MARGIN).toFloat();
        if (g != null) {
            var dy = ((g.y0 + y) - g.cy).abs() + rowH / 2.0;
            var half = dy >= g.r ? 0.0 : Math.sqrt(g.r * g.r - dy * dy);
            if (g.cx - half > lo) {
                lo = g.cx - half;
            }
            if (g.cx + half < hi) {
                hi = g.cx + half;
            }
            if (hi <= lo) {
                return [w / 2, 0] as Array<Number>;
            }
        }
        return [((lo + hi) / 2.0).toNumber(), (hi - lo).toNumber()] as Array<Number>;
    }

    // Centre y of row `row` when rows of the given heights are stacked in the cell: centred in
    // it when lean is 0, hard against the far edge when the stack is leaning away from a rim.
    // Always derived from the heights it is handed, so the fitter and the drawing code cannot
    // disagree about where a row ended up.
    function stackY(h as Number, heights as Array<Number>, row as Number,
            lean as Number) as Number {
        var total = 0;
        for (var i = 0; i < heights.size(); i++) {
            total += heights[i];
        }
        var y = (h - total) / 2;
        if (lean != 0 && total <= h - 2 * MARGIN) {
            y = lean > 0 ? h - MARGIN - total : MARGIN;
        }
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
            ladders as Array, caps as Array<Array<String> >, g as Glass?, lean as Number,
            hero as Number) as Array<Graphics.FontType> {
        var n = texts.size();
        var chosen = new Array<Graphics.FontType>[n];
        var heights = new Array<Number>[n];
        // The caption block is FONT_XTINY whatever the value's font turns out to be, so its
        // width is known before the ladder is walked and simply comes off every budget below.
        var capW = new Array<Number>[n];
        for (var i = 0; i < n; i++) {
            capW[i] = capWidth(dc, caps[i]);
        }
        // pass 1: every row gets the tallest font that fits the cell height budget alone
        var budget = (h - 2 * MARGIN) / n;
        for (var i = 0; i < n; i++) {
            chosen[i] = fitFont(dc, texts[i], w - 2 * MARGIN - capW[i], budget,
                ladders[i] as Array<Graphics.FontType>);
            heights[i] = dc.getFontHeight(chosen[i]);
        }
        // ...except the HERO row, which gets everything the others did not take.
        //
        // An equal slice is right for a stack of peers and wrong for a page with a giant on
        // it: five equal slices of a 454 px glass are 89 px, the smallest NUMBER font on a
        // fenix 8 is 113 px tall, and the app's Main page therefore came out with its giant in
        // FONT_LARGE and 83 px of glass left blank. Handing the hero the remainder instead is
        // a single allocation with nothing to undo — the sum still cannot exceed the cell, and
        // pass 2 below shrinks the hero again if the chord where it lands cannot hold it.
        //
        // A layout with no hero (HERO[size] < 0) skips this entirely, which is what keeps
        // every SMALL and WIDE cell fitted exactly as 0.9.4 fitted it.
        if (hero >= 0 && hero < n) {
            var used = 0;
            for (var i = 0; i < n; i++) {
                if (i != hero) {
                    used += heights[i];
                }
            }
            var room = h * HERO_STACK_PCT / 100 - used;
            if (room > h - 2 * MARGIN - used) {
                room = h - 2 * MARGIN - used;
            }
            chosen[hero] = fitFont(dc, texts[hero], w - 2 * MARGIN - capW[hero], room,
                ladders[hero] as Array<Graphics.FontType>);
            heights[hero] = dc.getFontHeight(chosen[hero]);
        }
        // pass 2: with the rows placed, re-fit each row to the width actually available
        // there — and then do it again, because a row that steps down MOVES every row in the
        // stack. It is tempting to assume one round is enough, since a shorter stack sits
        // closer to the middle of its cell; but the middle of a cell against the bottom rim is
        // itself well down the glass, so shrinking the flight line pushed the % above it
        // DOWNWARDS, into a chord narrower than the one it had just been measured against.
        // That is how a 129 px quadrant on the fr255 kept a number three pixels too wide.
        //
        // fitFont is capped by the height the row already has, so a round can only ever shrink
        // and the loop settles; three rounds is one more than any cell in the twelve layouts
        // Garmin offers has ever needed.
        for (var round = 0; round < REFITS; round++) {
            var settled = true;
            for (var i = 0; i < n; i++) {
                var y = stackY(h, heights, i, lean);
                var maxW = rowWindow(w, y, heights[i], g)[1] - capW[i];
                chosen[i] = fitFont(dc, texts[i], maxW, heights[i],
                    ladders[i] as Array<Graphics.FontType>);
                var fh = dc.getFontHeight(chosen[i]);
                if (fh != heights[i]) {
                    heights[i] = fh;
                    settled = false;
                }
            }
            if (settled) {
                break;
            }
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
