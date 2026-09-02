import Toybox.Graphics;
import Toybox.Lang;

// Metric glyphs and turn-outcome symbols, drawn with Dc primitives.
//
// Deliberately NOT bitmap resources: a bitmap would need one PNG per size per colour per
// product, would cost flash on a memory-tight watch, and could not be recoloured at runtime.
// Lines/arcs/polygons cost nothing but code, scale with the display, and stay crisp on both
// the MIP and the AMOLED variants.
//
// Every glyph draws inside an `s` x `s` box centred on (x, y) — that box is what the chord-fit
// maths in RecordingView measures, so a glyph can never be the thing that runs off the glass.
// Nothing here allocates: the only array is the module-level triangle scratch, filled in place.
module Glyphs {

    // Glyph ids. PageModel.glyph() maps a metric to one of these.
    enum {
        G_NONE = 0,
        G_WING = 1,        // hand wing: two nested domes + the strut between them
        G_WATCH = 2,       // stopwatch: circle, crown, hand
        G_RULER = 3,       // distance: a line with ticks
        G_HEART = 4,       // two lobes and a point
        G_BOLT = 5,        // speed: a zigzag
        G_TURN = 6,        // a hairpin u-arc with an arrow head
        G_PUMP = 7,        // pumping: a double-headed vertical arrow
        G_BATTERY = 8      // a cell with its nub
    }

    // Turn outcomes, as symbols instead of words (see RecordingView.drawTurnsPage).
    //
    // O_STAR is NOT a fourth rung of the ladder. The other three are the outcome — how the
    // turn ENDED — and they are mutually exclusive. A clean jibe is a stricter, separate
    // question (docs/presentation.md "Clean jibe"): a counted jibe whose carried-speed score
    // cleared the bar AND that never dropped off the foil across the scored window. Every
    // clean jibe is also a fly-through, so the star REPLACES the check where a row is known
    // to be one, and it is drawn in the clean-jibe ink, never the ladder's green.
    enum {
        O_DASH = 0,        // nothing scored yet
        O_CHECK = 1,       // flew through
        O_TRIANGLE = 2,    // touched down
        O_CROSS = 3,       // fell in
        O_STAR = 4         // a clean jibe (a fly-through that also carried its speed)
    }

    // Glyph edge, in pixels. Scaled off the display so the 416 px fenix 8 43 mm gets a
    // proportionally smaller mark than the 454 px 47 mm, then clamped into the 14-18 px band
    // that reads at arm's length through spray.
    const REF_SCREEN = 454;
    const REF_PX = 17;
    const MIN_PX = 14;
    const MAX_PX = 18;

    // Triangle scratch. Reused on every draw so the Turns page allocates nothing per redraw.
    var _tri as Array<Array<Number> > = [[0, 0], [0, 0], [0, 0]] as Array<Array<Number> >;

    // ---- the star (O_STAR) ----
    // Ten vertices — outer, inner, outer, ... — as THOUSANDTHS OF THE OUTER RADIUS, written
    // down rather than computed: `Math.sin` per vertex per redraw on a 1 Hz page is work the
    // watch does not need to repeat, and a table is also the only form a reviewer can check.
    // Angles run from the top, clockwise, 72 deg apart, with the inner ring offset by 36 deg.
    //
    // The inner radius is 0.45 of the outer, NOT the regular pentagram's 0.382. The glyph is
    // drawn at 14-18 px (see size()), where a 0.382 waist puts the arms at barely two pixels
    // and both the MIP quantiser and the AMOLED's own sub-pixel geometry eat them: at 14 px
    // the regular star reads as a blob with frayed edges. 0.45 keeps five arms visibly
    // separate at the floor size and is still unmistakably a star at 24 px.
    var _starU as Array<Array<Number> > = [
        [    0, -1000], [  265,  -364],     // top point, then down into the waist
        [  951,  -309], [  428,   139],
        [  588,   809], [    0,   450],
        [ -588,   809], [ -428,   139],
        [ -951,  -309], [ -265,  -364]
    ] as Array<Array<Number> >;

    // Star scratch, same no-allocation contract as `_tri`.
    var _star as Array<Array<Number> > = [
        [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
        [0, 0], [0, 0], [0, 0], [0, 0], [0, 0]
    ] as Array<Array<Number> >;

    function size(dc as Dc) as Number {
        var s = dc.getWidth() * REF_PX / REF_SCREEN;
        if (s < MIN_PX) {
            s = MIN_PX;
        }
        return s > MAX_PX ? MAX_PX : s;
    }

    // Draws glyph `g` centred at (x, y) inside an s x s box, in `col`.
    // Leaves the pen width at 1 and the colour at `col`.
    function draw(dc as Dc, g as Number, x as Number, y as Number, s as Number,
            col as Number) as Void {
        if (g == G_NONE) {
            return;
        }
        var h = s / 2;
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        if (g == G_WING) {
            // canopy: an outer and an inner dome sharing a baseline, plus the centre strut
            dc.drawArc(x, y + h - 1, h, Graphics.ARC_COUNTER_CLOCKWISE, 15, 165);
            dc.drawArc(x, y + h - 1, h / 2, Graphics.ARC_COUNTER_CLOCKWISE, 15, 165);
            dc.drawLine(x, y + h - 1 - h / 2, x, y + h - 1 - h);
        } else if (g == G_WATCH) {
            dc.drawCircle(x, y + 1, h - 1);
            dc.drawLine(x, y + 1 - h + 1, x, y + 1 - h - 1);      // crown
            dc.drawLine(x, y + 1, x, y + 1 - h + 4);              // hand
        } else if (g == G_RULER) {
            var yb = y + h / 2;
            dc.drawLine(x - h, yb, x + h, yb);
            dc.drawLine(x - h, yb, x - h, yb - h);
            dc.drawLine(x, yb, x, yb - h * 2 / 3);
            dc.drawLine(x + h, yb, x + h, yb - h);
        } else if (g == G_HEART) {
            var r = h / 2;
            var yl = y - h / 4;
            dc.drawArc(x - r, yl, r, Graphics.ARC_COUNTER_CLOCKWISE, 0, 180);
            dc.drawArc(x + r, yl, r, Graphics.ARC_COUNTER_CLOCKWISE, 0, 180);
            dc.drawLine(x - 2 * r, yl, x, y + h);
            dc.drawLine(x + 2 * r, yl, x, y + h);
        } else if (g == G_BOLT) {
            dc.drawLine(x + h / 2, y - h, x - h / 2, y);
            dc.drawLine(x - h / 2, y, x + h / 3, y);
            dc.drawLine(x + h / 3, y, x - h / 2, y + h);
        } else if (g == G_TURN) {
            var rt = h * 2 / 3;
            var yt = y - h / 4;
            dc.drawArc(x, yt, rt, Graphics.ARC_COUNTER_CLOCKWISE, 0, 180);
            dc.drawLine(x - rt, yt, x - rt, y + h);
            dc.drawLine(x + rt, yt, x + rt, y + h);
            dc.drawLine(x + rt, y + h, x + rt - 3, y + h - 4);    // arrow head
            dc.drawLine(x + rt, y + h, x + rt + 3, y + h - 4);
        } else if (g == G_PUMP) {
            dc.drawLine(x, y - h, x, y + h);
            dc.drawLine(x, y - h, x - 3, y - h + 4);
            dc.drawLine(x, y - h, x + 3, y - h + 4);
            dc.drawLine(x, y + h, x - 3, y + h - 4);
            dc.drawLine(x, y + h, x + 3, y + h - 4);
        } else if (g == G_BATTERY) {
            dc.drawRectangle(x - h, y - h / 2, s - 2, h);
            dc.fillRectangle(x + h - 2, y - h / 4, 2, h / 2);
        }
        dc.setPenWidth(1);
    }

    // Turn outcome as a symbol. Same box contract as draw(): s x s centred on (x, y).
    function drawOutcome(dc as Dc, o as Number, x as Number, y as Number, s as Number,
            col as Number) as Void {
        var h = s / 2;
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(s / 4 > 3 ? s / 4 : 3);
        if (o == O_CHECK) {
            dc.drawLine(x - h, y, x - h / 4, y + h * 3 / 4);
            dc.drawLine(x - h / 4, y + h * 3 / 4, x + h, y - h * 3 / 4);
        } else if (o == O_CROSS) {
            dc.drawLine(x - h, y - h, x + h, y + h);
            dc.drawLine(x - h, y + h, x + h, y - h);
        } else if (o == O_STAR) {
            drawStar(dc, x, y, s);
        } else if (o == O_TRIANGLE) {
            _tri[0][0] = x;
            _tri[0][1] = y - h;
            _tri[1][0] = x + h;
            _tri[1][1] = y + h;
            _tri[2][0] = x - h;
            _tri[2][1] = y + h;
            dc.fillPolygon(_tri as Array<Graphics.Point2D>);
        } else {
            dc.drawLine(x - h, y, x + h, y);
        }
        dc.setPenWidth(1);
    }

    // A filled five-point star inside the same s x s box every other glyph honours, in
    // whatever colour the caller has already set. Public because the Turns page draws the
    // mark on its own (beside a count) rather than as a row's outcome symbol.
    //
    // Integer arithmetic throughout, and the truncation is deliberately symmetric — `v * r`
    // divided by 1000 truncates toward zero on both signs — so the five arms stay the same
    // length as each other at every size, which is the one thing a small star cannot survive
    // getting wrong. Nothing allocates: `_star` is filled in place.
    function drawStar(dc as Dc, x as Number, y as Number, s as Number) as Void {
        var r = s / 2;
        for (var i = 0; i < 10; i++) {
            _star[i][0] = x + _starU[i][0] * r / 1000;
            _star[i][1] = y + _starU[i][1] * r / 1000;
        }
        dc.fillPolygon(_star as Array<Graphics.Point2D>);
    }
}
